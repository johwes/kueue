# Module 00: Setup and Installation

## The Problem: GPU Resource Sharing in ML/AI Workloads

### Why Can't We Just Use Separate Clusters?

In traditional application development, organizations typically maintain separate infrastructure for:
- **Development/Test environments** - for experimentation and testing
- **Production environments** - for serving customers

This separation works well when resources are inexpensive. However, **ML/AI workloads fundamentally change this equation:**

| Traditional (CPU/Memory) | ML/AI (GPU) |
|-------------------------|-------------|
| CPUs are relatively cheap | GPUs are 10-100x more expensive |
| Easy to provision separate clusters | Separate GPU clusters are cost-prohibitive |
| Dev/Test/Prod separation is standard | All workloads must share GPU infrastructure |

### The Multi-Tenancy Challenge

When multiple ML workload types share the same GPU cluster, you face critical challenges:

**Without Kueue:**
- ❌ Training experiments randomly consume all GPUs
- ❌ Production inference workloads are starved of resources
- ❌ SLA breaches impact customers
- ❌ No visibility into resource allocation
- ❌ Manual intervention required to resolve conflicts
- ❌ GPU utilization is inefficient (idle or fully saturated)

**With Kueue:**
- ✅ Production workloads get guaranteed resource quotas
- ✅ Training jobs use idle capacity intelligently
- ✅ Fair queueing prevents starvation
- ✅ Transparent visibility into workload admission
- ✅ Automatic resource management
- ✅ Maximum GPU utilization

## What is Red Hat Build of Kueue?

Kueue is a Kubernetes-native job queueing system that solves the multi-tenancy challenge by providing fair resource sharing, quota management, and intelligent workload admission control.

**Red Hat Build of Kueue** is an enterprise-supported operator that brings upstream Kueue capabilities to OpenShift:
- Hardened, tested builds of Kueue
- Enterprise support from Red Hat
- Integration with OpenShift AI and other Red Hat products
- Regular security updates and patches

## Prerequisites

- OpenShift cluster (4.17 or later recommended)
- Cluster administrator privileges
- `oc` CLI installed and logged in

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
