"""Compute one gain-relative energy threshold for every analysis stage."""
import numpy as np

RMS_FRACTION = 0.40
MARGIN_DB = float(-20 * np.log10(RMS_FRACTION))


def relative_energy_floor(energy):
    values = np.asarray(energy, dtype=float)
    if values.ndim != 1:
        raise ValueError("Energy must be one-dimensional")
    finite = values[np.isfinite(values)]
    if not len(finite):
        # No audible data: finite-energy checks reject every frame. The sentinel
        # only satisfies downstream parameter validation; it is not a dB cutoff.
        return None, 0.0
    reference = float(np.percentile(finite, 90))
    # Multiply linear RMS by the fraction in log space to avoid underflow.
    return reference, reference + float(20 * np.log10(RMS_FRACTION))
