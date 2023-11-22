# Ideas for implementing

## Pool Metrics

I want to make a simple way to analyze running pools to set their optimal configuration. For example, we launched a `pool` in production with a maximum overflow of 0 (we do not want to create more processes than the designated number) and a pool size 200.

Using metrics, we see that typically, our application uses 10-20 processes, and there are spikes when up to 180 workers are exploited. If our processes are heavyweight and, for example, open persistent connections to storage, then by analyzing metrics, we can significantly save resources. In this case, we can set the pool size to 20 and `max_overflow` to 180. This way, we will have one overall pool size limit of 200, and we will avoid uncontrolled waste of all resources, but at the same time, we will only keep up to 20 processes in memory at times when this is not required.

### Metrics to be implemented

- [ ] Pool size
  - [ ] Idle workers count
  - [ ] Busy workers count
  - [ ] Is max_overflow used?
  - [ ] Maximum count of "overflowed" workers
- [ ] Usage time
  - [ ] How long are workers busy?
  - [ ] How long the application waits of workers from pool?
  - [ ] How long pool is "overflowed"?

## Implementations metrics

To be described...
