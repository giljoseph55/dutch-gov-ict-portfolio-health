# Portfolio status report: large ICT projects, Dutch central government

**Scope:** 516 projects on the *Rijks ICT-dashboard*; latest status dates up to 1 Sep 2026 (most running projects last reported 31 Dec 2025).
**Basis:** public open data, outside view, data downloaded 20 Oct 2026. Thresholds are the author's convention; flags are not a judgement on project teams.
**Overall portfolio status: RED.** 91 of 156 projects in progress are Red.

| Indicator | Value | Source |
|---|---:|---|
| Projects more than 25% above first cost estimate | 49.4% of 431 | Q2 |
| Cost added since first estimates | €4,491m (+38.3%) | Q2 |
| Projects more than 12 months later than first planned | 47.9% of 472 | Q3 |
| In-progress projects Red / Amber / Green | 91 / 18 / 47 | Q7 |
| Over budget **and** late (both thresholds) | 154 of 429 | Q6 |

**RAG rule:** Red = cost growth above +25% or end date more than 12 months later than first estimate. Amber = above +10% or more than 3 months later. Green otherwise.

## Top risks

1. **Concentration in a few programmes.** ERTMS (rail signalling, Infrastructure and Water Management) has added €1,123m, a quarter of all cost growth in the portfolio. Programma iCAS (+€203m) and MOC KW (Coast Guard operations centre, +€184m) follow. The ten largest at-risk projects account for €2,085m, 46.4% of all cost growth in the portfolio (Q12).
2. **Long-running slips.** Eight of the ten at-risk projects now expect to finish five years or more after their first planned end date. Only ERTMS (2 years) and MOC KW (about 3.5 years) slipped less (Q4, Q12).
3. **Repeated re-plans.** MOC KW has re-planned 7 times, CHARM and LUV VTS 6 times each (Q4). Each reset moves the reference point, so status measured against the latest plan looks better than status measured against the first one.
4. **Weak schedule signal.** 45% of estimated end dates are entered as 31 December and no realised end dates are reported, so a slip shows up late and in year-sized steps (Q10).

## Recommendations

1. **Review cost on a fixed cycle for the whole project life, not only when a project re-plans.** From the 12-month mark, about 46% of projects still grow by more than 25%, and projects that did not re-plan in their first year grow just as often as those that did (Q11). A review triggered by re-plans would miss most of that growth. Put every dashboard project through an independent cost and schedule review at a set interval, for example yearly.
2. **Size contingency from the portfolio's own history.** New first estimates sit at the start of a distribution in which the median project grows +24.4% and half grow more than 25% (Q2). Hold contingency at portfolio level, sized on that distribution, instead of treating each first estimate as the expected cost. Apply the most caution below €20m, where percentage growth is highest (Q5).
3. **Report end dates by month and record the realised end date.** This turns schedule slip from a year-level after-the-fact number into a monthly signal, and lets the next review measure outcomes instead of estimates (Q10).

*Every figure is reproducible from `sql/queries.sql`; the query number is given beside it.*
