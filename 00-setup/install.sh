#!/bin/bash

set -e

echo "======================================"
echo "Red Hat Build of Kueue - Installation"
echo "======================================"
echo ""

# Check if logged in to OpenShift
if ! oc whoami &> /dev/null; then
    echo "❌ Error: Not logged in to OpenShift cluster"
    echo "Please run: oc login <your-cluster-url>"
    exit 1
fi

# Check cluster-admin permissions
if ! oc auth can-i '*' '*' --all-namespaces &> /dev/null; then
    echo "⚠️  Warning: You may not have cluster-admin privileges"
    echo "This installation requires cluster-admin access"
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

echo "✓ Logged in as: $(oc whoami)"
echo "✓ Cluster: $(oc whoami --show-server)"
echo ""

# Apply operator subscription
echo "📦 Installing Red Hat Build of Kueue operator..."
oc apply -f operator-subscription.yaml

echo ""
echo "⏳ Waiting for operator installation to complete..."
echo "   This may take a few minutes..."

# Wait for CSV to be created
for i in {1..60}; do
    if oc get csv -n openshift-operators 2>/dev/null | grep -q kueue; then
        break
    fi
    echo -n "."
    sleep 5
done
echo ""

# Wait for CSV to succeed
if ! oc wait --for=condition=Succeeded csv -l operators.coreos.com/kueue-operator.openshift-operators -n openshift-operators --timeout=300s 2>/dev/null; then
    echo "⚠️  Warning: CSV did not reach Succeeded state within timeout"
    echo "Checking current status..."
    oc get csv -n openshift-operators | grep kueue || echo "No Kueue CSV found"
else
    echo "✓ Operator CSV is ready"
fi

# Wait for operator pod to be ready
echo ""
echo "⏳ Waiting for operator pods to be ready..."
for i in {1..60}; do
    if oc get pods -n openshift-operators 2>/dev/null | grep -q "kueue.*Running"; then
        echo "✓ Operator pods are running"
        break
    fi
    echo -n "."
    sleep 5
done
echo ""

# Verify installation
echo ""
echo "======================================"
echo "Verifying Installation"
echo "======================================"
echo ""

echo "Operator Pods:"
oc get pods -n openshift-operators | grep kueue || echo "⚠️  No Kueue pods found"

echo ""
echo "Kueue CRDs:"
oc get crd | grep kueue || echo "⚠️  No Kueue CRDs found"

echo ""
echo "Operator Version:"
oc get csv -n openshift-operators | grep kueue || echo "⚠️  No Kueue CSV found"

echo ""
echo "======================================"
echo "Installation Complete!"
echo "======================================"
echo ""
echo "Next steps:"
echo "1. Review the installation with: oc get pods -n openshift-operators"
echo "2. Proceed to module 01-resource-configuration to create Kueue resources"
echo ""
