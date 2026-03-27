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

---

## Installation Overview

Red Hat Build of Kueue installation involves **two steps**:

1. **Install the Operator** - Deploys the Kueue operator
2. **Create Kueue Instance** - Deploys the Kueue controllers

This two-step process follows the [Red Hat documentation](https://docs.redhat.com/en/documentation/openshift_container_platform/4.19/html/ai_workloads/red-hat-build-of-kueue#create-kueue-cr_install-kueue).

---

## Installation Methods

### Method 1: Using the Automated Script (Recommended)

We've provided an automated installation script that handles both steps:

```bash
./install.sh
```

This script will:
1. ✅ Install the Kueue operator via Subscription
2. ✅ Wait for operator to be ready
3. ✅ Create the Kueue instance (CR)
4. ✅ Wait for kueue-controller-manager pods to be ready
5. ✅ Verify the complete installation

### Method 2: Manual Step-by-Step Installation

If you prefer manual control, follow these steps:

#### Step 1: Install the Operator

```bash
# Create operator subscription
oc apply -f operator-subscription.yaml

# Wait for CSV to succeed
oc wait --for=condition=Succeeded csv \
  -l operators.coreos.com/kueue-operator.openshift-operators \
  -n openshift-operators --timeout=300s

# Verify operator is running
oc get pods -n openshift-operators | grep openshift-kueue-operator
```

Expected output:
```
NAME                                        READY   STATUS    RESTARTS   AGE
openshift-kueue-operator-xxxxx-xxxxx        1/1     Running   0          2m
```

#### Step 2: Create Kueue Instance

```bash
# Create Kueue CR (deploys the actual Kueue controllers)
oc apply -f kueue-instance.yaml

# Wait for controller deployment
oc wait --for=condition=available deployment/kueue-controller-manager \
  -n openshift-operators --timeout=300s

# Verify controller pods are running
oc get pods -n openshift-operators | grep kueue-controller-manager
```

Expected output:
```
NAME                                        READY   STATUS    RESTARTS   AGE
kueue-controller-manager-xxxxx-xxxxx        2/2     Running   0          2m
```

---

## Understanding the Installation

### What Gets Installed?

**Operator (Step 1):**
- `openshift-kueue-operator` deployment
- Manages the Kueue lifecycle
- Watches for Kueue CRs

**Kueue Instance (Step 2):**
- `kueue-controller-manager` deployment
- Actual Kueue controllers that manage workloads
- Processes ClusterQueues, LocalQueues, and Workloads

### Files in This Directory

| File | Purpose |
|------|---------|
| `install.sh` | Automated installation script (both steps) |
| `operator-subscription.yaml` | Step 1: Operator installation |
| `kueue-instance.yaml` | Step 2: Kueue CR (creates controllers) |
| `README.md` | This documentation |

---

## Verification

After installation, verify all components are running:

### Check Operator

```bash
# Operator pods
oc get pods -n openshift-operators | grep openshift-kueue-operator

# Operator CSV
oc get csv -n openshift-operators | grep kueue
```

### Check Kueue Controllers

```bash
# Controller pods (deployed by Kueue CR)
oc get pods -n openshift-operators | grep kueue-controller-manager

# Kueue instance (CR)
oc get kueue cluster -n openshift-operators
```

### Check API Resources

Confirm Kueue CRDs are available:

```bash
oc api-resources | grep kueue.x-k8s.io
```

You should see:
- `clusterqueues` (cq)
- `localqueues` (queue, queues, lq)
- `resourceflavors` (flavor, flavors, rf)
- `workloads` (wl)
- `admissionchecks`
- `workloadpriorityclasses`
- `cohorts`

### Complete Verification

```bash
# All Kueue-related pods
oc get pods -n openshift-operators | grep kueue

# Expected output:
# openshift-kueue-operator-xxxxx        1/1     Running   0   5m
# kueue-controller-manager-xxxxx        2/2     Running   0   3m
```

---

## Troubleshooting

### Operator Not Starting

```bash
# Check operator logs
oc logs -n openshift-operators deployment/openshift-kueue-operator

# Check subscription status
oc get subscription kueue-operator -n openshift-operators -o yaml

# Check install plan
oc get installplan -n openshift-operators
```

### Kueue CR Not Creating Controllers

```bash
# Check Kueue CR status
oc get kueue cluster -n openshift-operators -o yaml

# Check for conditions
oc get kueue cluster -n openshift-operators -o jsonpath='{.status.conditions}' | jq

# Check operator logs (operator reconciles the Kueue CR)
oc logs -n openshift-operators deployment/openshift-kueue-operator
```

### Controller Pods Not Ready

```bash
# Check deployment status
oc get deployment kueue-controller-manager -n openshift-operators

# Check pod events
oc describe pod -n openshift-operators -l control-plane=controller-manager

# Check controller logs
oc logs -n openshift-operators deployment/kueue-controller-manager
```

### Permission Issues

Ensure you're logged in as cluster-admin:
```bash
oc whoami
oc auth can-i '*' '*' --all-namespaces
```

---

## Next Steps

Once the operator and controllers are installed and verified, proceed to create your first Kueue resources:

**Choose your learning path:**

- **Path 1 - Core Concepts:** [Module 01: Kueue Basics](../01-kueue-basics/) - Learn ResourceFlavors, ClusterQueues, and fair sharing
- **Path 2 - Advanced Features:** [Module 02: Borrowing & Preemption](../02-borrowing-preemption/) - Resource borrowing, cohorts, and priorities

---

## Additional Resources

- [Red Hat Build of Kueue Documentation](https://docs.redhat.com/en/documentation/red_hat_build_of_kueue/)
- [Creating a Kueue CR](https://docs.redhat.com/en/documentation/openshift_container_platform/4.19/html/ai_workloads/red-hat-build-of-kueue#create-kueue-cr_install-kueue)
- [Operator Installation Guide](https://docs.redhat.com/en/documentation/openshift_container_platform/4.17/html/operators/index)
- [Upstream Kueue Documentation](https://kueue.sigs.k8s.io/)
