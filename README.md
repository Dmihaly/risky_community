# Risk-based constraints for the optimal operation of an energy community


Data
--------
The data needed for the simulations can be found under this link:
...

Abstract
--------
This work formulates an energy community's centralized optimal bidding and scheduling problem as a time-series scenario-driven stochastic optimization model, building on real-life measurement data. In the presented model, a surrogate battery storage system with uncertain state-of-charge (SoC) bounds approximates the portfolio's aggregated flexibility. 
First, it is emphasized in a stylized analysis that risk-based energy constraints are highly beneficial (compared to chance-constraints) in coordinating distributed assets with unknown costs of constraint violation, as they limit both violation magnitude and probability. The presented research extends state-of-the-art models by implementing a worst-case conditional value at risk (WCVaR) based constraint for the storage SoC bounds. Then, an extensive numerical comparison is conducted to analyze the trade-off between out-of-sample violations and expected objective values, revealing that the proposed WCVaR based constraint shields significantly better against extreme out-of-sample outcomes than the conditional value at risk based equivalent.
To bypass the non-trivial task of capturing the underlying time and asset-dependent uncertain processes, real-life measurement data is directly leveraged for both imbalance market uncertainty and load forecast errors. For this purpose, a shape-based clustering method is implemented to capture the input scenarios' temporal characteristics.
This code is published as a companion material of the above named research, which is published in IEEE Transactions on Smart Grid and can be found on: https://www.mech.kuleuven.be/en/tme/research/energy-systems-integration-modeling/publications

License
--------
This work is licensed under a [Creative Commons Attribution 4.0 International License](http://creativecommons.org/licenses/by/4.0/)
