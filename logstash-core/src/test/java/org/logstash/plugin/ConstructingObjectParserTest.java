package org.logstash.plugin;

import org.junit.Test;
import org.junit.experimental.runners.Enclosed;
import org.junit.runner.RunWith;
import org.junit.runners.Parameterized;

import java.util.*;
import java.util.concurrent.atomic.AtomicReference;

import static org.junit.Assert.assertEquals;
import static org.junit.runners.Parameterized.Parameters;

@RunWith(Enclosed.class)
public class ConstructingObjectParserTest {
    public static class IntegrationTest {
        @Test
        public void testParsing() {
            ConstructingObjectParser<Example> c = new ConstructingObjectParser<>("example", (args) -> new Example());
            c.declareInteger("foo", Example::setValue);
            Map<String, Object> config = Collections.singletonMap("foo", 1);

            Example e = c.parse(config);
            assertEquals(1, e.getValue());
        }

        private class Example {
            private int i;

            int getValue() {
                return i;
            }

            void setValue(int i) {
                this.i = i;
            }
        }
    }

    @RunWith(Parameterized.class)
    public static class StringAccepts {
        private final Object input;
        private final Object expected;

        public StringAccepts(Object input, Object expected) {
            this.input = input;
            this.expected = expected;
        }

        @Parameters
        public static Collection<Object[]> data() {
            return Arrays.asList(new Object[][]{
                    {"1", "1"},
                    {1, "1"},
                    {1L, "1"},
                    {1F, "1.0"},
                    {1D, "1.0"},
            });
        }

        @Test
        public void testStringTransform() {
            AtomicReference<Object> x = new AtomicReference<>(); // a container for calling setters via lambda
            ConstructingObjectParser.<AtomicReference<Object>>stringTransform(AtomicReference::set).accept(x, input);
            assertEquals(expected, x.get());

        }
    }

    @RunWith(Parameterized.class)
    public static class StringRejections {
        private Object value;

        public StringRejections(Object value) {
            this.value = value;
        }

        @Parameters
        public static List<Object> data() {
            return Arrays.asList(new Object(), Collections.emptyMap(), Collections.emptyList());
        }

        @Test(expected = IllegalArgumentException.class)
        public void testFailure() {
            AtomicReference<Object> x = new AtomicReference<>(); // a container for calling setters via lambda
            ConstructingObjectParser.<AtomicReference<Object>>stringTransform(AtomicReference::set).accept(x, value);
        }
    }
}