# Data-driven risk-based scheduling of energy communities participating in day-ahead and real-time electricity markets


Data
--------
The data needed for the simulations can be found under this link:
...

Abstract
--------
This paper presents new risk-based constraints for the participation of an energy community in day-ahead and real-time energy markets. Forming communities offers indeed an effective way to manage the risk of the overall portfolio by pooling individual resources and associated uncertainties. However, the diversity of flexible resources and the related user-specific comfort constraints make it difficult to properly represent flexibility requirements and to monetize constraint violations.
To address these issues, we propose a new risk-aware probabilistic enforcement of flexibility constraints using the conditional-value-at-risk (CVaR). Next, an extended version of the model is introduced to mitigate the distributional ambiguity faced by the community manager when new sites with limited information are embedded in the portfolio. This is achieved by defining the worst-case CVaR based-constraint (WCVaR-BC) that differentiates the CVaR value among different sub-clusters of clients.
Both reformulations are linear, thus allowing to tackle large-scale stochastic problems. The proposed risk-based constraints are then trained and evaluated on real data collected from several industrial sites. Our findings indicate that using the WCVaR-BC leads to systematically higher out-of-sample reliability, while decreasing the exposure to extreme outcomes.
This code is published as a companion material of the above named research, which is currently submitted to IEEE Transactions on Power Systems and can be found on: https://www.mech.kuleuven.be/en/tme/research/energy-systems-integration-modeling/publications

License
--------
This work is licensed under a [Creative Commons Attribution 4.0 International License](http://creativecommons.org/licenses/by/4.0/)
