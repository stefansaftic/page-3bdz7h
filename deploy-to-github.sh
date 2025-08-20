#!/bin/bash

# GitHub Pages HTML Deployment Script
# Usage: ./deploy-to-github.sh <html-file>
# Creates a new GitHub repository with random name and deploys HTML file as GitHub Pages

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to generate random repository name
generate_repo_name() {
    # Generate 6 character random string using base32 encoding
    local random_string=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-6 | tr '[:upper:]' '[:lower:]')
    echo "page-${random_string}"
}

# Function to validate HTML file
validate_html_file() {
    local file="$1"
    
    # Check if file exists
    if [[ ! -f "$file" ]]; then
        print_error "File '$file' does not exist"
        return 1
    fi
    
    # Check if file has .html extension
    if [[ ! "$file" =~ \.html?$ ]]; then
        print_error "File '$file' is not an HTML file"
        return 1
    fi
    
    # Basic HTML validation - check for html tags
    if ! grep -qi "<html\|<HTML" "$file"; then
        print_warning "File '$file' may not be a valid HTML file (no <html> tag found)"
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            return 1
        fi
    fi
    
    return 0
}

# Function to check dependencies
check_dependencies() {
    print_status "Checking dependencies..."
    
    # Check if git is installed
    if ! command -v git &> /dev/null; then
        print_error "Git is not installed. Please install Git first."
        exit 1
    fi
    
    # Check if GitHub CLI is installed
    if ! command -v gh &> /dev/null; then
        print_error "GitHub CLI (gh) is not installed."
        print_error "Please install it from: https://cli.github.com/"
        exit 1
    fi
    
    # Check if GitHub CLI is authenticated
    if ! gh auth status &> /dev/null; then
        print_error "GitHub CLI is not authenticated."
        print_error "Please run: gh auth login"
        exit 1
    fi
    
    print_success "All dependencies are available"
}

# Function to create temporary git repository
create_temp_repo() {
    local html_file="$1"
    local repo_name="$2"
    local temp_dir="/tmp/gh-pages-deploy-$$"
    
    print_status "Creating temporary repository..."
    
    # Create temporary directory
    mkdir -p "$temp_dir"
    cd "$temp_dir"
    
    # Initialize git repository
    git init -q
    git config user.email "action@github.com"
    git config user.name "GitHub Pages Deploy"
    
    # Copy HTML file as index.html
    cp "$html_file" index.html
    print_success "Copied HTML file as index.html"
    
    # Create README.md
    cat > README.md << EOF
# $repo_name

Automatically deployed HTML file to GitHub Pages.

- **Deployed on**: $(date)
- **Original file**: $(basename "$html_file")
- **Live URL**: https://$(gh api user --jq '.login').github.io/$repo_name/

## About

This repository was created automatically using the deploy-to-github.sh script.
The HTML file is self-contained and ready to be served as a static website.
EOF
    
    # Create .gitignore
    cat > .gitignore << EOF
# macOS
.DS_Store

# Temporary files
*.tmp
*.temp

# Editor files
*.swp
*.swo
*~
EOF
    
    print_success "Created repository files"
    echo "$temp_dir"
}

# Function to deploy to GitHub
deploy_to_github() {
    local repo_name="$1"
    local temp_dir="$2"
    
    print_status "Deploying to GitHub..."
    
    cd "$temp_dir"
    
    # Add all files
    git add .
    git commit -q -m "Initial deployment of HTML file"
    
    # Create GitHub repository
    print_status "Creating GitHub repository: $repo_name"
    if ! gh repo create "$repo_name" --public --source . --push; then
        print_error "Failed to create GitHub repository"
        return 1
    fi
    
    print_success "Repository created and pushed to GitHub"
    
    # Enable GitHub Pages
    print_status "Enabling GitHub Pages..."
    sleep 2  # Wait a moment for repository to be fully created
    
    # Enable Pages using GitHub API
    if gh api repos/:owner/$repo_name/pages \
        --method POST \
        --field source.branch=main \
        --field source.path=/ \
        --silent 2>/dev/null; then
        print_success "GitHub Pages enabled"
    else
        print_warning "Could not automatically enable GitHub Pages"
        print_warning "Please enable it manually in repository settings"
    fi
    
    return 0
}

# Function to display results
show_results() {
    local repo_name="$1"
    local github_username=$(gh api user --jq '.login')
    
    echo
    print_success "Deployment completed successfully!"
    echo
    echo "📁 Repository Details:"
    echo "   Name: $repo_name"
    echo "   URL:  https://github.com/$github_username/$repo_name"
    echo
    echo "🌐 Live Website:"
    echo "   URL:  https://$github_username.github.io/$repo_name/"
    echo
    print_warning "Note: GitHub Pages may take a few minutes to become available"
    echo
}

# Function to cleanup
cleanup() {
    local temp_dir="$1"
    if [[ -n "$temp_dir" && -d "$temp_dir" ]]; then
        print_status "Cleaning up temporary files..."
        rm -rf "$temp_dir"
        print_success "Cleanup completed"
    fi
}

# Main function
main() {
    echo "🚀 GitHub Pages HTML Deployment Script"
    echo "======================================"
    echo
    
    # Check if HTML file argument is provided
    if [[ $# -eq 0 ]]; then
        print_error "Usage: $0 <html-file>"
        print_error "Example: $0 my-exported-file.html"
        exit 1
    fi
    
    local html_file="$1"
    local original_dir=$(pwd)
    local temp_dir=""
    
    # Convert relative path to absolute path
    if [[ ! "$html_file" = /* ]]; then
        html_file="$original_dir/$html_file"
    fi
    
    # Validate HTML file
    if ! validate_html_file "$html_file"; then
        exit 1
    fi
    
    # Check dependencies
    check_dependencies
    
    # Generate repository name
    local repo_name=$(generate_repo_name)
    print_status "Generated repository name: $repo_name"
    
    # Create temporary repository
    temp_dir=$(create_temp_repo "$html_file" "$repo_name")
    
    # Deploy to GitHub
    if deploy_to_github "$repo_name" "$temp_dir"; then
        show_results "$repo_name"
    else
        print_error "Deployment failed"
        cleanup "$temp_dir"
        exit 1
    fi
    
    # Cleanup
    cleanup "$temp_dir"
    
    print_success "All done! 🎉"
}

# Handle script interruption
trap 'echo; print_error "Script interrupted"; cleanup "$temp_dir"; exit 1' INT TERM

# Run main function
main "$@"
