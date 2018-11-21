package org.logstash.config.ir.compiler;

import org.jruby.RubyInteger;
import org.jruby.RubyString;
import org.jruby.runtime.builtin.IRubyObject;
import org.logstash.plugins.api.Filter;
import org.logstash.plugins.api.Output;

/**
 * This class holds interfaces implemented by Ruby concrete classes.
 */
public final class RubyIntegration {

    private RubyIntegration() {
        //Utility Class.
    }

    /**
     * Plugin Factory that instantiates Ruby plugins and is implemented in Ruby.
     */
    public interface PluginFactory {

        IRubyObject buildInput(RubyString name, RubyInteger line, RubyInteger column,
            IRubyObject args);

        AbstractOutputDelegatorExt buildOutput(RubyString name, RubyInteger line, RubyInteger column,
            IRubyObject args);

        AbstractOutputDelegatorExt buildJavaOutput(String name, int line, int column, Output output, IRubyObject args);

        AbstractFilterDelegatorExt buildFilter(RubyString name, RubyInteger line, RubyInteger column, IRubyObject args);

        AbstractFilterDelegatorExt buildJavaFilter(String name, int line, int column, Filter filter, IRubyObject args);

        IRubyObject buildCodec(RubyString name, IRubyObject args);
    }
}
