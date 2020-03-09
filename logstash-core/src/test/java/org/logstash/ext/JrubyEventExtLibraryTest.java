package org.logstash.ext;

import java.io.IOException;
import java.util.Arrays;
import java.util.Collections;
import java.util.HashMap;
import java.util.Map;
import org.assertj.core.api.Assertions;
import org.hamcrest.CoreMatchers;
import org.jruby.RubyHash;
import org.jruby.RubyString;
import org.jruby.exceptions.RuntimeError;
import org.jruby.javasupport.JavaUtil;
import org.jruby.runtime.ThreadContext;
import org.jruby.runtime.builtin.IRubyObject;
import org.junit.Assert;
import org.junit.Test;
import org.logstash.ObjectMappers;
import org.logstash.RubyUtil;

/**
 * Tests for {@link JrubyEventExtLibrary.RubyEvent}.
 */
public final class JrubyEventExtLibraryTest {

    @Test
    public void shouldSetJavaProxy() throws IOException {
        for (final Object proxy : Arrays.asList(getMapFixtureJackson(), getMapFixtureHandcrafted())) {
            final ThreadContext context = RubyUtil.RUBY.getCurrentContext();
            final JrubyEventExtLibrary.RubyEvent event =
                JrubyEventExtLibrary.RubyEvent.newRubyEvent(context.runtime);
            event.ruby_set_field(
                context, rubyString("[proxy]"),
                JavaUtil.convertJavaToUsableRubyObject(context.runtime, proxy)
            );
            final Map<String, IRubyObject> expected = new HashMap<>();
            expected.put("[string]", rubyString("foo"));
            expected.put("[int]", context.runtime.newFixnum(42));
            expected.put("[float]", context.runtime.newFloat(42.42));
            expected.put("[array][0]", rubyString("bar"));
            expected.put("[array][1]", rubyString("baz"));
            expected.put("[hash][string]", rubyString("quux"));
            expected.forEach(
                (key, value) -> Assertions.assertThat(
                    event.ruby_get_field(context, rubyString("[proxy]" + key))
                ).isEqualTo(value)
            );
        }
    }

    @Test
    public void correctlyHandlesNonAsciiKeys() {
        final RubyString key = rubyString("[テストフィールド]");
        final RubyString value = rubyString("someValue");
        final ThreadContext context = RubyUtil.RUBY.getCurrentContext();
        final JrubyEventExtLibrary.RubyEvent event =
            JrubyEventExtLibrary.RubyEvent.newRubyEvent(context.runtime);
        event.ruby_set_field(context, key, value);
        Assertions.assertThat(event.ruby_to_json(context, new IRubyObject[0]).asJavaString())
            .contains("\"テストフィールド\":\"someValue\"");
    }

    @Test
    public void correctlyRaiseRubyRuntimeErrorWhenGivenInvalidFieldReferences() {
        final ThreadContext context = RubyUtil.RUBY.getCurrentContext();
        final JrubyEventExtLibrary.RubyEvent event =
                JrubyEventExtLibrary.RubyEvent.newRubyEvent(context.runtime);
        final RubyString key = rubyString("il[[]]]legal");
        final RubyString value = rubyString("foo");
        try {
            event.ruby_set_field(context, key, value);
        } catch (RuntimeError rubyRuntimeError) {
            Assert.assertThat(rubyRuntimeError.getLocalizedMessage(), CoreMatchers.containsString("Invalid FieldReference"));
            return;
        }
        Assert.fail("expected ruby RuntimeError was not thrown.");
    }

    @Test
    public void correctlyRaiseRubyRuntimeErrorWhenGivenInvalidFieldReferencesInMap() {
        final ThreadContext context = RubyUtil.RUBY.getCurrentContext();
        final JrubyEventExtLibrary.RubyEvent event =
                JrubyEventExtLibrary.RubyEvent.newRubyEvent(context.runtime);
        final RubyString key = rubyString("foo");
        final RubyHash value = RubyHash.newHash(context.runtime, Collections.singletonMap(rubyString("il[[]]]legal"), rubyString("okay")), context.nil);
        try {
            event.ruby_set_field(context, key, value);
        } catch (RuntimeError rubyRuntimeError) {
            Assert.assertThat(rubyRuntimeError.getLocalizedMessage(), CoreMatchers.containsString("Invalid FieldReference"));
            return;
        }
        Assert.fail("expected ruby RuntimeError was not thrown.");
    }

    private static RubyString rubyString(final String java) {
        return RubyUtil.RUBY.newString(java);
    }

    private static Object getMapFixtureJackson() throws IOException {
        StringBuilder json = new StringBuilder();
        json.append('{');
        json.append("\"string\": \"foo\", ");
        json.append("\"int\": 42, ");
        json.append("\"float\": 42.42, ");
        json.append("\"array\": [\"bar\",\"baz\"], ");
        json.append("\"hash\": {\"string\":\"quux\"} }");
        return ObjectMappers.JSON_MAPPER.readValue(json.toString(), Object.class);
    }

    private static Map<String, Object> getMapFixtureHandcrafted() {
        HashMap<String, Object> inner = new HashMap<>();
        inner.put("string", "quux");
        HashMap<String, Object> map = new HashMap<>();
        map.put("string", "foo");
        map.put("int", 42);
        map.put("float", 42.42);
        map.put("array", Arrays.asList("bar", "baz"));
        map.put("hash", inner);
        return map;
    }
}
