#!/bin/bash

set -e

echo "======================================"
echo "Kueue Demo - Cleanup Script"
echo "======================================"
echo ""
echo "This script will remove all Kueue resources and the operator."
echo ""
echo "Resources to be deleted:"
echo "  - All jobs and workloads"
echo "  - LocalQueues"
echo "  - ClusterQueues"
echo "  - Cohorts"
echo "  - WorkloadPriorityClasses"
echo "  - ResourceFlavors"
echo "  - PVCs in ml-training namespace"
echo "  - ml-training and ml-inference namespaces"
echo "  - Kueue instance (CR)"
echo "  - Kueue operator"
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
echo "🗑️  Step 1/11: Deleting jobs and workloads..."
oc delete jobs --all -n ml-training 2>/dev/null || echo "  No jobs in ml-training"
oc delete jobs --all -n ml-inference 2>/dev/null || echo "  No jobs in ml-inference"
oc delete workloads --all -n ml-training 2>/dev/null || echo "  No workloads in ml-training"
oc delete workloads --all -n ml-inference 2>/dev/null || echo "  No workloads in ml-inference"
echo "  ✓ Jobs and workloads deleted"

# Step 2: Delete PVCs
echo ""
echo "🗑️  Step 2/11: Deleting PVCs..."
oc delete pvc --all -n ml-training 2>/dev/null || echo "  No PVCs in ml-training"
oc delete pvc --all -n ml-inference 2>/dev/null || echo "  No PVCs in ml-inference"
echo "  ✓ PVCs deleted"

# Step 3: Delete LocalQueues
echo ""
echo "🗑️  Step 3/11: Deleting LocalQueues..."
oc delete localqueue --all -n ml-training 2>/dev/null || echo "  No LocalQueues in ml-training"
oc delete localqueue --all -n ml-inference 2>/dev/null || echo "  No LocalQueues in ml-inference"
echo "  ✓ LocalQueues deleted"

# Step 4: Delete WorkloadPriorityClasses
echo ""
echo "🗑️  Step 4/11: Deleting WorkloadPriorityClasses..."
oc delete workloadpriorityclass --all 2>/dev/null || echo "  No WorkloadPriorityClasses found"
echo "  ✓ WorkloadPriorityClasses deleted"

# Step 5: Delete ClusterQueues
echo ""
echo "🗑️  Step 5/11: Deleting ClusterQueues..."
oc delete clusterqueue --all 2>/dev/null || echo "  No ClusterQueues found"
echo "  ✓ ClusterQueues deleted"

# Step 6: Delete Cohorts
echo ""
echo "🗑️  Step 6/11: Deleting Cohorts..."
oc delete cohort --all 2>/dev/null || echo "  No Cohorts found"
echo "  ✓ Cohorts deleted"

# Step 7: Delete ResourceFlavors
echo ""
echo "🗑️  Step 7/11: Deleting ResourceFlavors..."
oc delete resourceflavor --all 2>/dev/null || echo "  No ResourceFlavors found"
echo "  ✓ ResourceFlavors deleted"

# Step 8: Delete team namespaces
echo ""
echo "🗑️  Step 8/11: Deleting team namespaces..."
oc delete namespace ml-training 2>/dev/null || echo "  Namespace ml-training not found"
oc delete namespace ml-inference 2>/dev/null || echo "  Namespace ml-inference not found"
echo "  ✓ Namespaces deleted (or terminating)"

# Step 9: Delete Kueue CR instance
echo ""
echo "🗑️  Step 9/11: Deleting Kueue instance (CR)..."
oc delete kueue cluster -n openshift-operators 2>/dev/null || echo "  No Kueue instance found"
echo "  ⏳ Waiting for Kueue controllers to terminate..."
for i in {1..30}; do
    if ! oc get pods -n openshift-operators 2>/dev/null | grep -q kueue-controller-manager; then
        echo "  ✓ Kueue controllers terminated"
        break
    fi
    echo -n "."
    sleep 2
done
echo ""

# Step 10: Delete operator subscription and CSV
echo ""
echo "🗑️  Step 10/11: Deleting Kueue operator..."
oc delete subscription kueue-operator -n openshift-operators 2>/dev/null || echo "  Subscription not found"
CSV_NAME=$(oc get csv -n openshift-operators --no-headers 2>/dev/null | grep kueue | awk '{print $1}')
if [ -n "$CSV_NAME" ]; then
    oc delete csv "$CSV_NAME" -n openshift-operators 2>/dev/null
    echo "  ✓ Operator subscription and CSV deleted"
else
    echo "  No CSV found"
fi

echo "  ⏳ Waiting for operator pods to terminate..."
for i in {1..30}; do
    if ! oc get pods -n openshift-operators 2>/dev/null | grep -q kueue; then
        echo "  ✓ All Kueue operator pods terminated"
        break
    fi
    echo -n "."
    sleep 2
done
echo ""

# Step 11: Clean up webhooks
echo ""
echo "🗑️  Step 11/11: Deleting webhook configurations..."
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

CLEANUP_OK=true

echo "Jobs:"
if oc get jobs -n ml-training 2>/dev/null | grep -v NAME; then
    echo "  ⚠️  Jobs still exist in ml-training"
    CLEANUP_OK=false
fi
if oc get jobs -n ml-inference 2>/dev/null | grep -v NAME; then
    echo "  ⚠️  Jobs still exist in ml-inference"
    CLEANUP_OK=false
fi
if [ "$CLEANUP_OK" = true ]; then
    echo "  ✓ None"
fi

echo ""
echo "Workloads:"
if oc get workload -A 2>/dev/null | grep -v NAMESPACE; then
    echo "  ⚠️  Workloads still exist"
    CLEANUP_OK=false
else
    echo "  ✓ None"
fi

echo ""
echo "PVCs:"
if oc get pvc -n ml-training 2>/dev/null | grep -v NAME; then
    echo "  ⚠️  PVCs still exist in ml-training"
    CLEANUP_OK=false
fi
if oc get pvc -n ml-inference 2>/dev/null | grep -v NAME; then
    echo "  ⚠️  PVCs still exist in ml-inference"
    CLEANUP_OK=false
fi
if [ "$CLEANUP_OK" = true ]; then
    echo "  ✓ None"
fi

echo ""
echo "LocalQueues:"
if oc get localqueue -A 2>/dev/null | grep -v NAMESPACE; then
    echo "  ⚠️  LocalQueues still exist"
    CLEANUP_OK=false
else
    echo "  ✓ None"
fi

echo ""
echo "WorkloadPriorityClasses:"
if oc get workloadpriorityclass 2>/dev/null | grep -v NAME; then
    echo "  ⚠️  WorkloadPriorityClasses still exist"
    CLEANUP_OK=false
else
    echo "  ✓ None"
fi

echo ""
echo "ClusterQueues:"
if oc get clusterqueue 2>/dev/null | grep -v NAME; then
    echo "  ⚠️  ClusterQueues still exist"
    CLEANUP_OK=false
else
    echo "  ✓ None"
fi

echo ""
echo "Cohorts:"
if oc get cohort 2>/dev/null | grep -v NAME; then
    echo "  ⚠️  Cohorts still exist"
    CLEANUP_OK=false
else
    echo "  ✓ None"
fi

echo ""
echo "ResourceFlavors:"
if oc get resourceflavor 2>/dev/null | grep -v NAME; then
    echo "  ⚠️  ResourceFlavors still exist"
    CLEANUP_OK=false
else
    echo "  ✓ None"
fi

echo ""
echo "Namespaces:"
if oc get namespace ml-training 2>/dev/null; then
    echo "  ⚠️  ml-training namespace still exists (may be terminating)"
fi
if oc get namespace ml-inference 2>/dev/null; then
    echo "  ⚠️  ml-inference namespace still exists (may be terminating)"
fi
if ! oc get namespace ml-training 2>/dev/null && ! oc get namespace ml-inference 2>/dev/null; then
    echo "  ✓ Deleted"
fi

echo ""
echo "Kueue Instance (CR):"
if oc get kueue cluster -n openshift-operators 2>/dev/null; then
    echo "  ⚠️  Kueue CR still exists"
    CLEANUP_OK=false
else
    echo "  ✓ None"
fi

echo ""
echo "Kueue Operator Pods:"
if oc get pods -n openshift-operators 2>/dev/null | grep kueue; then
    echo "  ⚠️  Kueue pods still running"
    CLEANUP_OK=false
else
    echo "  ✓ None"
fi

echo ""
echo "Kueue CRDs:"
echo "  (CRDs are left in place - they don't affect new installations)"
oc get crd 2>/dev/null | grep kueue | awk '{print "    - " $1}' || echo "  ✓ None"

echo ""
echo "======================================"
if [ "$CLEANUP_OK" = true ]; then
    echo "✅ Cleanup Complete - All Resources Removed!"
else
    echo "⚠️  Cleanup Complete with Warnings"
    echo ""
    echo "Some resources may still be terminating."
    echo "Wait a few moments and check again with:"
    echo "  oc get all -n ml-training"
    echo "  oc get all -n ml-inference"
    echo "  oc get clusterqueue,cohort,resourceflavor"
fi
echo "======================================"
echo ""
echo "The cluster is ready for a fresh installation."
echo ""
echo "To reinstall and run the demos:"
echo "  cd 00-setup"
echo "  ./install.sh"
echo ""
echo "Then choose your learning path:"
echo "  cd ../01-kueue-basics/00-setup    # Core concepts"
echo "  cd ../02-borrowing-preemption/00-setup  # Advanced features"
echo ""
