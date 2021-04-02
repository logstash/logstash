/*
 * Licensed to Elasticsearch B.V. under one or more contributor
 * license agreements. See the NOTICE file distributed with
 * this work for additional information regarding copyright
 * ownership. Elasticsearch B.V. licenses this file to you under
 * the Apache License, Version 2.0 (the "License"); you may
 * not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *	http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing,
 * software distributed under the License is distributed on an
 * "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 * KIND, either express or implied.  See the License for the
 * specific language governing permissions and limitations
 * under the License.
 */


package org.logstash;

import com.fasterxml.jackson.databind.annotation.JsonDeserialize;
import com.fasterxml.jackson.databind.annotation.JsonSerialize;

import java.time.Instant;
import java.util.Date;
import org.joda.time.DateTime;
import org.joda.time.DateTimeZone;
import org.logstash.ackedqueue.Queueable;

/**
 * Wrapper around a {@link Instant} with Logstash specific serialization behaviour.
 * This class is immutable and thread-safe since its only state is held in a final {@link Instant}
 * reference and {@link Instant} which itself is immutable and thread-safe.
 */
@JsonSerialize(using = ObjectMappers.TimestampSerializer.class)
@JsonDeserialize(using = ObjectMappers.TimestampDeserializer.class)
public final class Timestamp implements Comparable<Timestamp>, Queueable {

    private transient DateTime time;

    private final Instant instant;

    public Timestamp() {
        this(Instant.now());
    }

    public Timestamp(String iso8601) {
        this(Instant.parse(iso8601));
    }

    public Timestamp(long epoch_milliseconds) {
        this(Instant.ofEpochMilli(epoch_milliseconds));
    }

    public Timestamp(final Date date) {
        this(date.toInstant());
    }

    public Timestamp(final DateTime date) {
        this(date.getMillis());
    }

    public Timestamp(final Instant instant) {
        this.instant = instant;
    }

    @Deprecated // use Timestamp#getInstant()
    public DateTime getTime() {
        if (time == null) {
            time = new DateTime(instant.toEpochMilli(), DateTimeZone.UTC);
        }
        return time;
    }

    public Instant getInstant() {
        return this.getInstant();
    }

    public static Timestamp now() {
        return new Timestamp();
    }

    public String toString() {
        return instant.toString();
    }

    public long toEpochMilli() {
        return instant.toEpochMilli();
    }

    // returns the fraction of a second as microseconds, not the number of microseconds since epoch
    public long usec() {
        return instant.getNano() / 1000;
    }

    @Override
    public int compareTo(Timestamp other) {
        return instant.compareTo(other.instant);
    }
    
    @Override
    public boolean equals(final Object other) {
        return other instanceof Timestamp && instant.equals(((Timestamp) other).instant);
    }

    @Override
    public int hashCode() {
        return instant.hashCode();
    }

    @Override
    public byte[] serialize() {
        return toString().getBytes();
    }
}
