# Best Practices: Production Deployment

This guide provides production-ready patterns for deploying Kueue with borrowing and preemption at scale.

## Table of Contents

1. [Checkpoint Strategies](#checkpoint-strategies)
2. [Priority Class Design](#priority-class-design)
3. [Borrowing Policies](#borrowing-policies)
4. [Monitoring Preemption](#monitoring-preemption)
5. [Cost Optimization](#cost-optimization)
6. [Troubleshooting](#troubleshooting)

---

## Checkpoint Strategies

### Checkpoint Frequency Trade-offs

| Frequency | Work Loss | I/O Overhead | Storage | Best For |
|-----------|-----------|--------------|---------|----------|
| Every step | 0% | Very High | Large | Critical workloads |
| Every 10 steps | < 1% | Medium | Medium | Short jobs (< 1 hour) |
| Every 100 steps | < 5% | Low | Small | Medium jobs (1-10 hours) |
| Every 5 minutes | 5 min | Very Low | Small | Long jobs (> 10 hours) |
| No checkpoint | 100% | None | None | Stateless / Idempotent only |

**Recommendation:** For ML training, checkpoint every 5-10 minutes or every N epochs, whichever is more frequent.

---

### PyTorch Checkpoint Example

```python
import torch
import os

def save_checkpoint(model, optimizer, epoch, checkpoint_path):
    """Save training checkpoint"""
    checkpoint = {
        'epoch': epoch,
        'model_state_dict': model.state_dict(),
        'optimizer_state_dict': optimizer.state_dict(),
        'loss': loss,
    }
    torch.save(checkpoint, checkpoint_path)
    print(f"Checkpoint saved at epoch {epoch}")

def load_checkpoint(model, optimizer, checkpoint_path):
    """Load training checkpoint"""
    if os.path.exists(checkpoint_path):
        checkpoint = torch.load(checkpoint_path)
        model.load_state_dict(checkpoint['model_state_dict'])
        optimizer.load_state_dict(checkpoint['optimizer_state_dict'])
        start_epoch = checkpoint['epoch'] + 1
        print(f"Resuming from epoch {start_epoch}")
        return start_epoch
    return 0  # Start from beginning

# Training loop with checkpointing
start_epoch = load_checkpoint(model, optimizer, "/checkpoint/model.pt")

for epoch in range(start_epoch, max_epochs):
    # Training logic
    train(model, data_loader, optimizer)

    # Checkpoint every epoch
    save_checkpoint(model, optimizer, epoch, "/checkpoint/model.pt")
```

**Job YAML Integration:**
```yaml
spec:
  template:
    spec:
      containers:
      - name: trainer
        volumeMounts:
        - name: checkpoint
          mountPath: /checkpoint
      volumes:
      - name: checkpoint
        persistentVolumeClaim:
          claimName: training-checkpoint-pvc
```

---

### TensorFlow Checkpoint Example

```python
import tensorflow as tf

# Create checkpoint manager
checkpoint_dir = '/checkpoint'
checkpoint = tf.train.Checkpoint(
    optimizer=optimizer,
    model=model
)
manager = tf.train.CheckpointManager(
    checkpoint, directory=checkpoint_dir, max_to_keep=3
)

# Restore latest checkpoint if exists
checkpoint.restore(manager.latest_checkpoint)
if manager.latest_checkpoint:
    print(f"Restored from {manager.latest_checkpoint}")
    start_epoch = int(manager.latest_checkpoint.split('-')[-1])
else:
    print("Initializing from scratch")
    start_epoch = 0

# Training loop
for epoch in range(start_epoch, max_epochs):
    # Training logic
    train_step(data, model, optimizer)

    # Save checkpoint every epoch
    manager.save()
```

---

## Priority Class Design

### Three-Tier Priority System (Recommended)

```yaml
---
apiVersion: kueue.x-k8s.io/v1beta1
kind: WorkloadPriorityClass
metadata:
  name: critical
value: 10000
description: "Production-critical: Customer-facing inference, SLA-bound workloads"
---
apiVersion: kueue.x-k8s.io/v1beta1
kind: WorkloadPriorityClass
metadata:
  name: high
value: 1000
description: "High priority: Important training, scheduled batch jobs"
---
apiVersion: kueue.x-k8s.io/v1beta1
kind: WorkloadPriorityClass
metadata:
  name: best-effort
value: 100
description: "Best-effort: Experiments, can be preempted anytime"
```

**Priority Matrix:**
```
critical (10000):
  - Real-time inference
  - Customer-facing APIs
  - SLA-critical batch jobs
  - Can preempt: high, best-effort
  - Cannot be preempted by: anything

high (1000):
  - Scheduled production training
  - Important experiments with deadlines
  - CI/CD model validation
  - Can preempt: best-effort
  - Can be preempted by: critical

best-effort (100):
  - Research experiments
  - Hyperparameter tuning
  - Exploratory analysis
  - Can preempt: nothing
  - Can be preempted by: high, critical
```

---

### Priority Assignment Guidelines

**Use `critical` for:**
- Services with customer SLAs
- Revenue-generating workloads
- Real-time inference endpoints
- Compliance-required jobs

**Use `high` for:**
- Scheduled model training (e.g., nightly retraining)
- Important experiments with deadlines
- Model validation before deployment
- Data pipeline processing

**Use `best-effort` for:**
- Exploratory research
- Hyperparameter search
- Experiments without deadlines
- Development/testing workloads

**Anti-Pattern:** Don't make everything `critical` - this defeats the purpose!

---

## Borrowing Policies

### Conservative Borrowing (Recommended for Production)

```yaml
preemption:
  reclaimWithinCohort: Any
  borrowWithinCohort:
    policy: Never  # Only use truly idle resources
  withinClusterQueue: LowerPriority
```

**Behavior:**
- Only borrow completely idle resources
- Don't preempt nominal quota of other queues
- Conservative, predictable

**Use when:**
- Production workloads need predictability
- SLAs are strict
- Teams need guaranteed minimums

---

### Aggressive Borrowing (Maximum Utilization)

```yaml
preemption:
  reclaimWithinCohort: Any
  borrowWithinCohort:
    policy: LowerPriority  # Can borrow and preempt lower priority
  withinClusterQueue: LowerPriority
```

**Behavior:**
- Can borrow from other queues even if they have pending workloads
- Will preempt lower-priority workloads across queues
- Maximizes utilization but less predictable

**Use when:**
- Research clusters
- Cost optimization is top priority
- Teams understand they might be preempted

---

### Hybrid Approach (Best of Both Worlds)

Create separate cohorts for different workload types:

```yaml
---
# Production cohort (conservative)
apiVersion: kueue.x-k8s.io/v1beta2
kind: ClusterQueue
metadata:
  name: production-inference-cq
spec:
  cohort: production-pool
  preemption:
    borrowWithinCohort:
      policy: Never  # Conservative
  resourceGroups:
  - flavors:
    - name: default-flavor
      resources:
      - name: cpu
        nominalQuota: 20
---
# Research cohort (aggressive)
apiVersion: kueue.x-k8s.io/v1beta2
kind: ClusterQueue
metadata:
  name: research-training-cq
spec:
  cohort: research-pool
  preemption:
    borrowWithinCohort:
      policy: LowerPriority  # Aggressive
  resourceGroups:
  - flavors:
    - name: default-flavor
      resources:
      - name: cpu
        nominalQuota: 30
```

**Result:**
- Production workloads: Predictable, guaranteed resources
- Research workloads: Maximum utilization, opportunistic borrowing
- Best of both worlds!

---

## Monitoring Preemption

### Key Metrics to Track

1. **Preemption Rate** - How often jobs are preempted
2. **Recovery Time** - Time from preemption to readmission
3. **Checkpoint Overhead** - I/O time spent checkpointing
4. **Work Lost** - Time between last checkpoint and preemption

---

### Prometheus Metrics (Red Hat Build of Kueue)

```promql
# Preemption events per hour
rate(kueue_workload_evictions_total[1h])

# Pending workloads waiting for resources
kueue_pending_workloads{cluster_queue="training-cluster-queue"}

# Admitted workloads currently running
kueue_admitted_workloads_total{cluster_queue="training-cluster-queue"}

# Resource utilization (borrowed resources)
kueue_cluster_queue_resource_reservation{resource="cpu",cluster_queue="training-cluster-queue",flavor="default-flavor"}
```

---

### Checking Preemption Events with CLI

```bash
# View recent preemption events
oc get events -A --field-selector reason=Evicted

# Count preemptions in last hour
oc get events -A --field-selector reason=Evicted \
  -o json | jq '[.items[] | select(.lastTimestamp > "'$(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ)'")]  | length'

# Check workload eviction status
oc get workload -A -o json | jq '.items[] | select(.status.conditions[] | select(.type=="Evicted" and .status=="True")) | .metadata.name'
```

---

### Setting Up Alerts

Example Prometheus alert rules:

```yaml
groups:
- name: kueue_alerts
  rules:
  # Alert if preemption rate is too high
  - alert: HighPreemptionRate
    expr: rate(kueue_workload_evictions_total[1h]) > 10
    for: 15m
    annotations:
      summary: "High workload preemption rate detected"
      description: "More than 10 preemptions per hour in the last 15 minutes"

  # Alert if workloads stuck in queue too long
  - alert: WorkloadsStuckInQueue
    expr: kueue_pending_workloads > 5
    for: 30m
    annotations:
      summary: "Workloads stuck in queue"
      description: "More than 5 workloads pending for over 30 minutes"
```

---

## Cost Optimization

### 1. Right-Size Nominal Quotas

**Anti-Pattern:**
```yaml
training-cq:   nominalQuota: 50 CPUs  (team only uses 20 on average)
inference-cq:  nominalQuota: 10 CPUs  (team needs 30 during peak)
```

**Better:**
```yaml
training-cq:   nominalQuota: 20 CPUs  (actual average usage)
inference-cq:  nominalQuota: 30 CPUs  (actual peak usage)
# Total: 50 CPUs (same as before)
# But better aligned to actual needs
```

**Impact:**
- Inference gets guaranteed resources during peak
- Training still borrows during off-peak
- No wasted reservations

---

### 2. Use Spot/Preemptible ResourceFlavors

```yaml
---
apiVersion: kueue.x-k8s.io/v1beta1
kind: ResourceFlavor
metadata:
  name: spot-flavor
spec:
  nodeLabels:
    node.kubernetes.io/instance-type: spot
---
apiVersion: kueue.x-k8s.io/v1beta2
kind: ClusterQueue
metadata:
  name: research-cq
spec:
  resourceGroups:
  - flavors:
    - name: spot-flavor  # Cheaper, can be terminated
      resources:
      - name: cpu
        nominalQuota: 100
    - name: on-demand-flavor  # Expensive, guaranteed
      resources:
      - name: cpu
        nominalQuota: 20
```

**Result:**
- Research uses cheap spot instances (save 60-70%)
- Critical workloads use on-demand (guaranteed availability)

---

### 3. Time-Based Quota Adjustment

Use CronJobs to adjust quotas based on time of day:

```bash
# Expand inference quota during business hours (9 AM)
0 9 * * * oc patch clusterqueue inference-cq --type='json' -p='[{"op": "replace", "path": "/spec/resourceGroups/0/flavors/0/resources/0/nominalQuota", "value": "40"}]'

# Reduce inference quota during off-hours (6 PM)
0 18 * * * oc patch clusterqueue inference-cq --type='json' -p='[{"op": "replace", "path": "/spec/resourceGroups/0/flavors/0/resources/0/nominalQuota", "value": "10"}]'
```

**Impact:**
- Inference gets more resources during business hours (customer traffic)
- Training gets more resources at night (experiments)
- Maximize utilization 24/7

---

### 4. Memory Efficiency (This Workshop Pattern)

**Our demo pattern:**
```yaml
resources:
  requests:
    cpu: "3"
    memory: "64Mi"  # Ultra-low for cost efficiency
```

**Why this matters at scale:**
```
100 users × 64Mi  = 6.4GB total memory
100 users × 1Gi   = 100GB total memory (16x more expensive!)
```

**Production recommendation:**
- Request only what you actually need
- Use resource quotas to prevent over-requesting
- Monitor actual usage vs. requested

---

## Troubleshooting

### Problem: Jobs Stuck in Pending After Preemption

**Symptom:**
```bash
oc get workload -n ml-training
# NAME          ADMITTED   EVICTED   AGE
# job-xxx       False      True      10m  ← Should have been readmitted!
```

**Diagnosis:**
```bash
# Check ClusterQueue capacity
oc get clusterqueue training-cq -o json | jq '.status.flavorsReservation'

# Check if resources are actually available
oc get clusterqueue training-cq -o yaml | grep -A 10 "resourceGroups"
```

**Common causes:**
1. Resources still in use by other workloads
2. Insufficient cluster capacity (quota > actual nodes)
3. Node selector mismatch

**Solution:**
```bash
# Wait for resources to free up, or
# Temporarily increase quota if cluster has capacity:
oc patch clusterqueue training-cq --type='json' \
  -p='[{"op": "replace", "path": "/spec/resourceGroups/0/flavors/0/resources/0/nominalQuota", "value": "5"}]'
```

---

### Problem: Preemption Not Happening

**Symptom:** High-priority job submitted but low-priority job not preempted

**Diagnosis:**
```bash
# Check priority classes are assigned
oc get workload <workload-name> -o jsonpath='{.spec.priorityClassName}'

# Check preemption policy
oc get clusterqueue <cq-name> -o yaml | grep -A 10 "preemption"
```

**Common causes:**
1. Missing priority class label on job
2. Preemption disabled (`reclaimWithinCohort: Never`)
3. Low-priority job using nominal quota (not borrowed)

**Solution:**
```yaml
metadata:
  labels:
    kueue.x-k8s.io/priority-class: high-priority  # Add this!
```

---

### Problem: Checkpoint File Not Persisting

**Symptom:** Job resumes from 0% instead of last checkpoint

**Diagnosis:**
```bash
# Check PVC is bound
oc get pvc -n ml-training

# Check PVC contents
oc run pvc-check --image=ubi9/ubi-minimal --restart=Never \
  --overrides='{"spec":{"containers":[{"name":"check","image":"registry.access.redhat.com/ubi9/ubi-minimal","command":["ls","-la","/checkpoint"],"volumeMounts":[{"name":"checkpoint","mountPath":"/checkpoint"}]}],"volumes":[{"name":"checkpoint","persistentVolumeClaim":{"claimName":"training-checkpoint-pvc"}}]}}'

oc logs pvc-check
```

**Common causes:**
1. PVC not mounted correctly
2. File written to wrong path
3. PVC storage class doesn't support RWO

**Solution:** Verify volumeMount path matches script path exactly.

---

## Production Deployment Checklist

### Before Going to Production

- [ ] **Checkpoint frequency** defined and tested
- [ ] **Priority classes** created and documented
- [ ] **Borrowing policies** set appropriately for workload type
- [ ] **Monitoring** configured (Prometheus, alerts)
- [ ] **PVC backup** strategy in place
- [ ] **Quota alignment** verified (quota ≤ actual cluster capacity)
- [ ] **Documentation** updated for team workflows
- [ ] **Runbooks** created for common issues
- [ ] **Load testing** completed with realistic workloads
- [ ] **Cost analysis** showing ROI vs. alternatives

---

## Additional Resources

- [Kueue Preemption Policies](https://kueue.sigs.k8s.io/docs/concepts/cluster_queue/#preemption)
- [WorkloadPriorityClass Design](https://kueue.sigs.k8s.io/docs/concepts/workload_priority_class/)
- [Cohort Resource Sharing](https://kueue.sigs.k8s.io/docs/concepts/cluster_queue/#cohort)
- [Red Hat Build of Kueue Documentation](https://docs.redhat.com/en/documentation/red_hat_build_of_kueue/)
- [PyTorch Checkpointing](https://pytorch.org/tutorials/beginner/saving_loading_models.html)
- [TensorFlow Checkpointing](https://www.tensorflow.org/guide/checkpoint)
