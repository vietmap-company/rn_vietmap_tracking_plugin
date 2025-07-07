#!/bin/bash

# GPS Tracking Package Deployment Script
# This script helps deploy the React Native GPS tracking package

set -e

echo "🚀 Starting GPS Tracking Package Deployment"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if we're in the right directory
if [ ! -f "package.json" ]; then
    print_error "package.json not found. Are you in the package root directory?"
    exit 1
fi

# Check if package name is correct
PACKAGE_NAME=$(node -p "require('./package.json').name")
if [ "$PACKAGE_NAME" != "rn_vietmap_tracking_plugin" ]; then
    print_error "Package name mismatch. Expected 'rn_vietmap_tracking_plugin', got '$PACKAGE_NAME'"
    exit 1
fi

print_status "Package name: $PACKAGE_NAME"

# Check current version
CURRENT_VERSION=$(node -p "require('./package.json').version")
print_status "Current version: $CURRENT_VERSION"

# Clean previous builds
print_status "Cleaning previous builds..."
rm -rf lib/
rm -rf node_modules/.cache/

# Install dependencies
print_status "Installing dependencies..."
npm install

# Run linting
print_status "Running ESLint..."
npm run lint || print_warning "Linting found issues"

# Run TypeScript check
print_status "Running TypeScript check..."
npm run typescript || {
    print_error "TypeScript check failed"
    exit 1
}

# Run tests
print_status "Running tests..."
npm test || {
    print_error "Tests failed"
    exit 1
}

# Build package
print_status "Building package..."
npm run prepare || {
    print_error "Build failed"
    exit 1
}

# Check if lib directory was created
if [ ! -d "lib" ]; then
    print_error "Build failed - lib directory not created"
    exit 1
fi

print_status "Build successful"

# Verify package contents
print_status "Verifying package contents..."
if [ ! -f "lib/module/index.js" ]; then
    print_error "Module build not found"
    exit 1
fi

if [ ! -f "lib/typescript/src/index.d.ts" ]; then
    print_error "TypeScript definitions not found"
    exit 1
fi

print_status "Package contents verified"

# Check if git is clean
if ! git diff-index --quiet HEAD --; then
    print_warning "Git working directory is not clean. Consider committing changes first."
    read -p "Continue anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Version bump prompt
echo
print_status "Current version: $CURRENT_VERSION"
echo "Select version bump type:"
echo "1) patch (1.0.0 -> 1.0.1)"
echo "2) minor (1.0.0 -> 1.1.0)"
echo "3) major (1.0.0 -> 2.0.0)"
echo "4) custom version"
echo "5) skip version bump"

read -p "Enter choice (1-5): " version_choice

case $version_choice in
    1)
        print_status "Bumping patch version..."
        npm version patch --no-git-tag-version
        ;;
    2)
        print_status "Bumping minor version..."
        npm version minor --no-git-tag-version
        ;;
    3)
        print_status "Bumping major version..."
        npm version major --no-git-tag-version
        ;;
    4)
        read -p "Enter custom version: " custom_version
        npm version $custom_version --no-git-tag-version
        ;;
    5)
        print_status "Skipping version bump..."
        ;;
    *)
        print_error "Invalid choice"
        exit 1
        ;;
esac

# Get new version
NEW_VERSION=$(node -p "require('./package.json').version")
print_status "New version: $NEW_VERSION"

# Rebuild with new version
if [ "$version_choice" != "5" ]; then
    print_status "Rebuilding with new version..."
    npm run prepare
fi

# Create git commit and tag
if [ "$version_choice" != "5" ]; then
    print_status "Creating git commit and tag..."
    git add .
    git commit -m "chore: bump version to $NEW_VERSION"
    git tag "v$NEW_VERSION"
fi

# Pack and test
print_status "Testing package..."
npm pack --dry-run

echo
print_status "Package is ready for deployment!"
echo
echo "To publish:"
echo "1. Manual publish: npm publish"
echo "2. Using release-it: npm run release"
echo
echo "To test locally:"
echo "1. Create tarball: npm pack"
echo "2. Install in test project: npm install ../path/to/rn_vietmap_tracking_plugin-$NEW_VERSION.tgz"
echo

# Ask if user wants to publish now
read -p "Do you want to publish to npm now? (y/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    print_status "Publishing to npm..."
    npm publish
    print_status "Package published successfully!"

    # Push git changes
    print_status "Pushing git changes..."
    git push origin main
    git push origin --tags

    print_status "Deployment completed successfully! 🎉"
else
    print_status "Skipping npm publish. You can publish later with: npm publish"
fi

echo
print_status "Deployment script completed!"
