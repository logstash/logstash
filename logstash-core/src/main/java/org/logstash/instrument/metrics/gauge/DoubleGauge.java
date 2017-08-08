package org.logstash.instrument.metrics.gauge;

import org.logstash.instrument.metrics.MetricType;

/**
 * A {@link GaugeMetric} that is backed by a {@link Double}
 */
public class DoubleGauge extends AbstractGaugeMetric<Double> {

    /**
     * Constructor
     *
     * @param name The name of this metric. This value may be used for display purposes.
     */
    public DoubleGauge(String name) {
        super(name);
    }

    /**
     * Constructor
     *
     * @param name         The name of this metric. This value may be used for display purposes.
     * @param initialValue The initial value for this {@link GaugeMetric}, may be null
     */
    public DoubleGauge(String name, Double initialValue) {
        super(name, initialValue);
    }

    @Override
    public MetricType getType() {
        return MetricType.GAUGE_DOUBLE;
    }

}

