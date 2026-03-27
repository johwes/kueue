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

# ==========================================
# STEP 1: Install the Operator
# ==========================================
echo "======================================"
echo "Step 1: Installing Kueue Operator"
echo "======================================"
echo ""

echo "📦 Creating operator subscription..."
oc apply -f operator-subscription.yaml

echo ""
echo "⏳ Waiting for operator CSV to be created..."
echo "   This may take a few minutes..."

# Wait for CSV to be created
for i in {1..60}; do
    if oc get csv -n openshift-operators 2>/dev/null | grep -q kueue; then
        echo ""
        echo "✓ CSV created"
        break
    fi
    echo -n "."
    sleep 5
done

# Wait for CSV to succeed
echo "⏳ Waiting for operator CSV to reach Succeeded state..."
if ! oc wait --for=condition=Succeeded csv -l operators.coreos.com/kueue-operator.openshift-operators -n openshift-operators --timeout=300s 2>/dev/null; then
    echo "⚠️  Warning: CSV did not reach Succeeded state within timeout"
    echo "Checking current status..."
    oc get csv -n openshift-operators | grep kueue || echo "No Kueue CSV found"
    echo ""
    echo "You may need to check the operator logs:"
    echo "  oc logs -n openshift-operators deployment/openshift-kueue-operator"
    exit 1
else
    echo "✓ Operator CSV is ready"
fi

# Wait for operator pod to be ready
echo ""
echo "⏳ Waiting for operator pods to be ready..."
for i in {1..60}; do
    if oc get pods -n openshift-operators 2>/dev/null | grep -E "openshift-kueue-operator.*Running" > /dev/null; then
        echo "✓ Operator pods are running"
        break
    fi
    if [ $i -eq 60 ]; then
        echo "⚠️  Warning: Operator pods not running after 5 minutes"
        oc get pods -n openshift-operators | grep kueue || echo "No Kueue pods found"
    fi
    echo -n "."
    sleep 5
done
echo ""

# ==========================================
# STEP 2: Create Kueue Instance
# ==========================================
echo ""
echo "======================================"
echo "Step 2: Creating Kueue Instance (CR)"
echo "======================================"
echo ""

echo "📦 Creating Kueue custom resource..."
oc apply -f kueue-instance.yaml

echo ""
echo "⏳ Waiting for Kueue CR to be created..."
sleep 5

# Check if Kueue CR exists
if oc get kueue cluster -n openshift-operators &>/dev/null; then
    echo "✓ Kueue CR created"
else
    echo "❌ Kueue CR not found"
    echo "Checking available Kueue CRs:"
    oc get kueue -A
    exit 1
fi

# Wait for kueue-controller-manager deployment to be created
echo ""
echo "⏳ Waiting for Kueue controller deployment to be created..."
for i in {1..60}; do
    if oc get deployment kueue-controller-manager -n openshift-operators &>/dev/null; then
        echo "✓ Kueue controller deployment created"
        break
    fi
    if [ $i -eq 60 ]; then
        echo "⚠️  Warning: kueue-controller-manager deployment not created after 5 minutes"
        echo "Checking Kueue CR status:"
        oc get kueue cluster -n openshift-operators -o yaml
        exit 1
    fi
    echo -n "."
    sleep 5
done
echo ""

# Wait for kueue-controller-manager pods to be ready
echo "⏳ Waiting for Kueue controller pods to be ready..."
if ! oc wait --for=condition=available deployment/kueue-controller-manager -n openshift-operators --timeout=300s 2>/dev/null; then
    echo "⚠️  Warning: kueue-controller-manager deployment not available within timeout"
    echo "Checking deployment status:"
    oc get deployment kueue-controller-manager -n openshift-operators
    echo ""
    echo "Checking pods:"
    oc get pods -n openshift-operators | grep kueue-controller-manager
else
    echo "✓ Kueue controller pods are ready"
fi

# ==========================================
# STEP 3: Verify Installation
# ==========================================
echo ""
echo "======================================"
echo "Verifying Installation"
echo "======================================"
echo ""

echo "Operator Pods:"
oc get pods -n openshift-operators | grep openshift-kueue-operator || echo "⚠️  No operator pods found"

echo ""
echo "Kueue Controller Pods:"
oc get pods -n openshift-operators | grep kueue-controller-manager || echo "⚠️  No controller pods found"

echo ""
echo "Kueue CR Status:"
oc get kueue cluster -n openshift-operators || echo "⚠️  No Kueue CR found"

echo ""
echo "Kueue CRDs:"
oc api-resources | grep kueue.x-k8s.io | awk '{print "  - " $1}' || echo "⚠️  No Kueue CRDs found"

echo ""
echo "Operator Version:"
oc get csv -n openshift-operators | grep kueue || echo "⚠️  No Kueue CSV found"

echo ""
echo "======================================"
echo "Installation Complete!"
echo "======================================"
echo ""
echo "Next steps:"
echo "1. Verify Kueue is working:"
echo "   oc get clusterqueue"
echo "   oc get resourceflavor"
echo ""
echo "2. Proceed to Module 01 to create Kueue resources:"
echo "   cd ../01-kueue-basics/00-setup"
echo ""
