# Module 00: Setup and Installation

This module covers installing the Red Hat Build of Kueue operator on your OpenShift cluster.

## Prerequisites

- OpenShift cluster (4.17 or later recommended)
- Cluster administrator privileges
- `oc` CLI installed and logged in

## What is Red Hat Build of Kueue?

Red Hat Build of Kueue is an enterprise-supported operator that brings upstream Kueue capabilities to OpenShift. It provides:
- Hardened, tested builds of Kueue
- Enterprise support from Red Hat
- Integration with OpenShift AI and other Red Hat products
- Regular security updates and patches

## Installation Methods

### Method 1: Using the OpenShift Web Console (Recommended)

1. Log in to the OpenShift web console as a cluster administrator
2. Navigate to **Operators → OperatorHub**
3. Search for "Kueue"
4. Select **Red Hat Build of Kueue**
5. Click **Install**
6. Configure installation options:
   - **Update Channel**: `stable`
   - **Installation Mode**: `All namespaces on the cluster`
   - **Installed Namespace**: `openshift-operators`
   - **Update Approval**: `Automatic` (or `Manual` for production)
7. Click **Install**
8. Wait for the operator to reach "Succeeded" status

### Method 2: Using CLI (Automated Script)

We've provided an automated installation script:

```bash
./install.sh
```

This script will:
1. Create the necessary namespace
2. Create an OperatorGroup
3. Create a Subscription to install the operator
4. Wait for installation to complete
5. Verify the installation

### Method 3: Manual CLI Installation

If you prefer manual control, follow these steps:

```bash
# Create operator namespace (if not using openshift-operators)
oc create namespace kueue-system

# Create operator subscription
oc apply -f operator-subscription.yaml

# Wait for CSV to be ready
oc wait --for=condition=Succeeded csv -l operators.coreos.com/kueue-operator.openshift-operators -n openshift-operators --timeout=300s
```

## Verification

After installation, verify the operator is running:

```bash
# Check operator pod status
oc get pods -n openshift-operators | grep kueue

# Verify CRDs are installed
oc get crd | grep kueue

# Check operator version
oc get csv -n openshift-operators | grep kueue
```

Expected output:
```
NAME                                         READY   STATUS    RESTARTS   AGE
kueue-controller-manager-xxxxx-xxxxx         2/2     Running   0          2m
```

## Verify API Resources

Confirm Kueue resources are available:

```bash
oc api-resources | grep kueue
```

You should see:
- `clusterqueues` (cq)
- `localqueues` (queue, queues, lq)
- `resourceflavors` (flavor, flavors, rf)
- `workloads` (wl)
- `admissionchecks`
- `workloadpriorityclasses`

## Configuration

The operator is now installed but not configured. You'll create your first Kueue resources in the next module.

## Troubleshooting

### Operator not starting

```bash
# Check operator logs
oc logs -n openshift-operators deployment/kueue-controller-manager

# Check events
oc get events -n openshift-operators --sort-by='.lastTimestamp'
```

### CRDs not appearing

```bash
# Verify subscription status
oc get subscription kueue-operator -n openshift-operators -o yaml

# Check install plan
oc get installplan -n openshift-operators
```

### Permission Issues

Ensure you're logged in as cluster-admin:
```bash
oc whoami
oc auth can-i '*' '*' --all-namespaces
```

## Next Steps

Once the operator is installed and verified, proceed to [01-resource-configuration](../01-resource-configuration/README.md) to create your first Kueue resources.

## Additional Resources

- [Red Hat Build of Kueue Documentation](https://docs.redhat.com/en/documentation/red_hat_build_of_kueue/1.0/)
- [Operator Installation Guide](https://docs.redhat.com/en/documentation/openshift_container_platform/4.17/html/operators/index)
