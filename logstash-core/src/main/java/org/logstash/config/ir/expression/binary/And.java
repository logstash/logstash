package org.logstash.config.ir.expression.binary;

import org.logstash.common.SourceWithMetadata;
import org.logstash.config.ir.expression.BinaryBooleanExpression;
import org.logstash.config.ir.expression.Expression;

public class And extends BinaryBooleanExpression {
    public And(SourceWithMetadata meta, Expression left, Expression right) {
        super(meta, left, right);
    }

    @Override
    public String rubyOperator() {
        return "&&";
    }
}
