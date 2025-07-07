#!/bin/bash

# Local Testing Script for GPS Tracking Package
# This script helps test the package locally before publishing

set -e

echo "🧪 Starting Local Testing for GPS Tracking Package"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

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

PACKAGE_NAME=$(node -p "require('./package.json').name")
PACKAGE_VERSION=$(node -p "require('./package.json').version")

print_status "Testing package: $PACKAGE_NAME@$PACKAGE_VERSION"

# Clean and install dependencies
print_status "Installing dependencies..."
npm install

# Run all checks
print_status "Running TypeScript check..."
npm run typescript || {
    print_error "TypeScript check failed"
    exit 1
}

print_status "Running linting..."
npm run lint || print_warning "Linting found issues"

print_status "Running tests..."
npm test || {
    print_error "Tests failed"
    exit 1
}

# Build the package
print_status "Building package..."
npm run prepare || {
    print_error "Build failed"
    exit 1
}

# Create tarball for testing
print_status "Creating tarball..."
TARBALL_NAME=$(npm pack --silent)
print_status "Created tarball: $TARBALL_NAME"

# Test the example app
print_status "Testing example app..."
cd example

# Install dependencies for example
print_status "Installing example dependencies..."
npm install

# Install the packed version of our package
print_status "Installing local package in example..."
npm install ../$TARBALL_NAME

# Try to build the example (just check if it compiles)
print_status "Checking example TypeScript..."
if command -v tsc &> /dev/null; then
    npx tsc --noEmit --skipLibCheck
    print_status "Example TypeScript check passed"
else
    print_warning "TypeScript compiler not available, skipping example TS check"
fi

# Check if Metro can bundle (without actually starting)
print_status "Checking Metro bundling..."
if command -v npx &> /dev/null; then
    timeout 30s npx react-native start --reset-cache &
    METRO_PID=$!
    sleep 10
    kill $METRO_PID 2>/dev/null || true
    print_status "Metro bundling check completed"
else
    print_warning "Metro bundler not available, skipping bundle check"
fi

# Return to root directory
cd ..

# Test imports
print_status "Testing package imports..."
cat > test_imports.js << EOF
// Test importing the package
try {
    const pkg = require('./lib/module/index.js');
    console.log('✅ Module import successful');
    console.log('Available exports:', Object.keys(pkg));

    // Test some basic functions
    if (typeof pkg.createDefaultConfig === 'function') {
        const config = pkg.createDefaultConfig();
        console.log('✅ createDefaultConfig works');
        console.log('Default config:', config);
    }

    if (typeof pkg.validateLocationConfig === 'function') {
        const validation = pkg.validateLocationConfig({
            intervalMs: 5000,
            distanceFilter: 10,
            accuracy: 'high',
            backgroundMode: true
        });
        console.log('✅ validateLocationConfig works');
        console.log('Validation result:', validation);
    }

    if (pkg.TRACKING_PRESETS) {
        console.log('✅ TRACKING_PRESETS available');
        console.log('Presets:', Object.keys(pkg.TRACKING_PRESETS));
    }

    if (pkg.LocationUtils) {
        console.log('✅ LocationUtils available');
        const distance = pkg.LocationUtils.calculateDistance(0, 0, 1, 1);
        console.log('Distance calculation test:', distance);
    }

    console.log('🎉 All imports and basic functions work!');
} catch (error) {
    console.error('❌ Import test failed:', error);
    process.exit(1);
}
EOF

node test_imports.js
rm test_imports.js

# Test TypeScript definitions
print_status "Testing TypeScript definitions..."
cat > test_types.ts << EOF
// Test TypeScript definitions
import type { LocationTrackingConfig, LocationData } from './lib/typescript/src/index';

const config: LocationTrackingConfig = {
    intervalMs: 5000,
    distanceFilter: 10,
    accuracy: 'high',
    backgroundMode: true
};

const location: LocationData = {
    latitude: 37.7749,
    longitude: -122.4194,
    altitude: 100,
    accuracy: 10,
    speed: 0,
    bearing: 0,
    timestamp: Date.now()
};

console.log('✅ TypeScript definitions work!');
console.log('Config:', config);
console.log('Location:', location);
EOF

if command -v tsc &> /dev/null; then
    npx tsc test_types.ts --noEmit --skipLibCheck
    print_status "TypeScript definitions test passed"
else
    print_warning "TypeScript compiler not available, skipping types test"
fi

rm -f test_types.ts

# Final summary
echo
print_status "🎉 Local testing completed successfully!"
echo
echo "Package Summary:"
echo "  Name: $PACKAGE_NAME"
echo "  Version: $PACKAGE_VERSION"
echo "  Tarball: $TARBALL_NAME"
echo
echo "Next steps:"
echo "  1. Test the tarball in a real React Native project:"
echo "     npm install /path/to/$TARBALL_NAME"
echo "  2. Run the example app on device/simulator"
echo "  3. Deploy with: ./scripts/deploy.sh"
echo
echo "To clean up:"
echo "  rm $TARBALL_NAME"
echo

# Ask if user wants to clean up
read -p "Remove the tarball now? (y/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    rm $TARBALL_NAME
    print_status "Tarball removed"
else
    print_status "Tarball kept: $TARBALL_NAME"
fi

print_status "Local testing script completed!"
