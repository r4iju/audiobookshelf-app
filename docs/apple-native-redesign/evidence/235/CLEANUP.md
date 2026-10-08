# Owned resource cleanup

Audit: 2026-10-08T05:02:56.291176+00:00

Capture backend/proxy sessions93630/39013 stopped with SIGINT; initial owned before-fixture sessions25194/40547/96691 were already stopped. Each verify harness exited and cleaned its own fixtures. Both T3 devices were closed with shutdown=true, then their pool leases released.

```text
19765: no listener
19766: no listener
19767: no listener
19769: no listener
25765: no listener
25769: no listener
51769: no listener

Owned iPad CDFFEB30-07F5-4A50-AB64-57A46709335B: Shutdown/free after release.
Owned phone75FA9768-B15C-40B6-ACC7-790D7FCAD29C: our release returned0. It was immediately acquired/booted by another workflow before the audit; that lease is not ours and was not touched.

```

No owner account reset, public upload, production NAS call, push, PR, metadata/STATE/ticket edit or other platform source change. Raw temporary logs/results remain under/tmp.
