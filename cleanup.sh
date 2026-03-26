#!/bin/bash

set -e

echo "======================================"
echo "Kueue Demo - Cleanup Script"
echo "======================================"
echo ""
echo "This script will remove all Kueue resources and the operator."
echo ""
read -p "Are you sure you want to proceed? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cleanup cancelled."
    exit 0
fi

echo ""
echo "Starting cleanup..."
echo ""

# Step 1: Delete jobs and workloads
echo "🗑️  Deleting jobs and workloads..."
oc delete jobs --all -n team-alpha 2>/dev/null || echo "  No jobs in team-alpha"
oc delete jobs --all -n team-beta 2>/dev/null || echo "  No jobs in team-beta"
oc delete workloads --all -n team-alpha 2>/dev/null || echo "  No workloads in team-alpha"
oc delete workloads --all -n team-beta 2>/dev/null || echo "  No workloads in team-beta"
echo "  ✓ Jobs and workloads deleted"

# Step 2: Delete LocalQueues
echo ""
echo "🗑️  Deleting LocalQueues..."
oc delete localqueue --all -n team-alpha 2>/dev/null || echo "  No LocalQueues in team-alpha"
oc delete localqueue --all -n team-beta 2>/dev/null || echo "  No LocalQueues in team-beta"
echo "  ✓ LocalQueues deleted"

# Step 3: Delete ClusterQueues
echo ""
echo "🗑️  Deleting ClusterQueues..."
oc delete clusterqueue --all 2>/dev/null || echo "  No ClusterQueues found"
echo "  ✓ ClusterQueues deleted"

# Step 4: Delete ResourceFlavors
echo ""
echo "🗑️  Deleting ResourceFlavors..."
oc delete resourceflavor --all 2>/dev/null || echo "  No ResourceFlavors found"
echo "  ✓ ResourceFlavors deleted"

# Step 5: Delete team namespaces
echo ""
echo "🗑️  Deleting team namespaces..."
oc delete namespace team-alpha 2>/dev/null || echo "  Namespace team-alpha not found"
oc delete namespace team-beta 2>/dev/null || echo "  Namespace team-beta not found"
echo "  ✓ Namespaces deleted"

# Step 6: Delete Kueue CR instance
echo ""
echo "🗑️  Deleting Kueue CR instance..."
oc delete kueue cluster 2>/dev/null || echo "  No Kueue instance found"
echo "  Waiting for Kueue controller to terminate..."
sleep 10
echo "  ✓ Kueue instance deleted"

# Step 7: Delete operator subscription
echo ""
echo "🗑️  Deleting Kueue operator subscription..."
oc delete subscription kueue-operator -n openshift-operators 2>/dev/null || echo "  Subscription not found"
echo "  ✓ Subscription deleted"

# Step 8: Delete CSV
echo ""
echo "🗑️  Deleting ClusterServiceVersion..."
CSV_NAME=$(oc get csv -n openshift-operators --no-headers 2>/dev/null | grep kueue | awk '{print $1}')
if [ -n "$CSV_NAME" ]; then
    oc delete csv "$CSV_NAME" -n openshift-operators 2>/dev/null
    echo "  ✓ CSV $CSV_NAME deleted"
else
    echo "  No CSV found"
fi

# Step 9: Wait for operator pods to terminate
echo ""
echo "⏳ Waiting for operator pods to terminate..."
for i in {1..30}; do
    if ! oc get pods -n openshift-operators 2>/dev/null | grep -q kueue; then
        echo "  ✓ All Kueue pods terminated"
        break
    fi
    echo -n "."
    sleep 2
done
echo ""

# Step 10: Delete CRDs (optional - commented out by default)
echo ""
echo "🗑️  CRD cleanup (optional)..."
echo "  Note: CRDs are NOT deleted by default to avoid cluster-wide impact."
echo "  To delete CRDs manually, run:"
echo "    oc delete crd -l app.kubernetes.io/name=kueue"
echo ""

# Step 11: Clean up webhooks
echo "🗑️  Deleting webhook configurations..."
oc delete validatingwebhookconfiguration kueue-validating-webhook-configuration 2>/dev/null || echo "  Validating webhook not found"
oc delete mutatingwebhookconfiguration kueue-mutating-webhook-configuration 2>/dev/null || echo "  Mutating webhook not found"
echo "  ✓ Webhooks deleted"

# Verification
echo ""
echo "======================================"
echo "Cleanup Verification"
echo "======================================"
echo ""

echo "Checking for remaining resources..."
echo ""

echo "ClusterQueues:"
oc get clusterqueue 2>/dev/null || echo "  None (✓)"

echo ""
echo "LocalQueues:"
oc get localqueue -A 2>/dev/null || echo "  None (✓)"

echo ""
echo "ResourceFlavors:"
oc get resourceflavor 2>/dev/null || echo "  None (✓)"

echo ""
echo "Workloads:"
oc get workload -A 2>/dev/null || echo "  None (✓)"

echo ""
echo "Kueue Operator Pods:"
oc get pods -n openshift-operators 2>/dev/null | grep kueue || echo "  None (✓)"

echo ""
echo "Kueue CRDs (still present):"
oc get crd 2>/dev/null | grep kueue || echo "  None"

echo ""
echo "======================================"
echo "Cleanup Complete!"
echo "======================================"
echo ""
echo "The cluster is now ready for a fresh installation."
echo ""
echo "To reinstall Kueue, start with:"
echo "  cd 00-setup"
echo "  ./install.sh"
echo ""
