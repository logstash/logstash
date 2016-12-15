package org.logstash.ackedqueue.ext;

import org.logstash.Event;
import org.logstash.ext.JrubyEventExtLibrary;
import org.jruby.Ruby;
import org.jruby.RubyClass;
import org.jruby.RubyFixnum;
import org.jruby.RubyModule;
import org.jruby.RubyObject;
import org.jruby.RubyBoolean;
import org.jruby.anno.JRubyClass;
import org.jruby.anno.JRubyMethod;
import org.jruby.runtime.Arity;
import org.jruby.runtime.ObjectAllocator;
import org.jruby.runtime.ThreadContext;
import org.jruby.runtime.builtin.IRubyObject;
import org.jruby.runtime.load.Library;
import org.logstash.ackedqueue.Batch;
import org.logstash.ackedqueue.MemorySettings;
import org.logstash.ackedqueue.Queue;
import org.logstash.ackedqueue.Settings;
import org.logstash.common.io.ByteBufferPageIO;
import org.logstash.common.io.CheckpointIOFactory;
import org.logstash.common.io.MemoryCheckpointIO;
import org.logstash.common.io.PageIOFactory;

import java.io.IOException;

public class JrubyAckedQueueMemoryExtLibrary implements Library {

    public void load(Ruby runtime, boolean wrap) throws IOException {
        RubyModule module = runtime.defineModule("LogStash");

        RubyClass clazz = runtime.defineClassUnder("AckedMemoryQueue", runtime.getObject(), new ObjectAllocator() {
            public IRubyObject allocate(Ruby runtime, RubyClass rubyClass) {
                return new RubyAckedMemoryQueue(runtime, rubyClass);
            }
        }, module);

        clazz.defineAnnotatedMethods(RubyAckedMemoryQueue.class);
    }

    // TODO:
    // as a simplified first prototyping implementation, the Settings class is not exposed and the queue elements
    // are assumed to be logstash Event.


    @JRubyClass(name = "AckedMemoryQueue", parent = "Object")
    public static class RubyAckedMemoryQueue extends RubyObject {
        private Queue queue;

        public RubyAckedMemoryQueue(Ruby runtime, RubyClass klass) {
            super(runtime, klass);
        }

        public Queue getQueue() {
            return this.queue;
        }

        // def initialize
        @JRubyMethod(name = "initialize", optional = 5)
        public IRubyObject ruby_initialize(ThreadContext context, IRubyObject[] args)
        {
            args = Arity.scanArgs(context.runtime, args, 5, 0);

            int capacity = RubyFixnum.num2int(args[1]);
            int maxUnread = RubyFixnum.num2int(args[2]);
            long queueMaxBytes = RubyFixnum.num2long(args[3]);
            String className = args[4].asJavaString();

            Settings s = new MemorySettings(args[0].asJavaString());
            PageIOFactory pageIOFactory = (pageNum, size, path) -> new ByteBufferPageIO(pageNum, size, path);
            CheckpointIOFactory checkpointIOFactory = (source) -> new MemoryCheckpointIO(source);
            s.setCapacity(capacity);
            s.setMaxUnread(maxUnread);
            s.setQueueMaxBytes(queueMaxBytes);
            s.setElementIOFactory(pageIOFactory);
            s.setCheckpointIOFactory(checkpointIOFactory);

            try {
                s.setElementClass(Class.forName(className));
            } catch (ClassNotFoundException e) {
                context.runtime.newArgumentError("[" + className + "] class not found");
            }

            this.queue = new Queue(s);

            return context.nil;
        }

        @JRubyMethod(name = "max_unread_events")
        public IRubyObject ruby_max_unread_events(ThreadContext context) {
            return context.runtime.newFixnum(queue.getMaxUnread());
        }

        @JRubyMethod(name = "max_size_in_bytes")
        public IRubyObject ruby_max_size_in_bytes(ThreadContext context) {
            return context.runtime.newFixnum(queue.getMaxBytes());
        }

        @JRubyMethod(name = "page_capacity")
        public IRubyObject ruby_page_capacity(ThreadContext context) {
            return context.runtime.newFixnum(queue.getPageCapacity());
        }

        @JRubyMethod(name = "dir_path")
        public IRubyObject ruby_dir_path(ThreadContext context) {
            return context.runtime.newString(queue.getDirPath());
        }

        @JRubyMethod(name = "current_byte_size")
        public IRubyObject ruby_current_byte_size(ThreadContext context) {
            return context.runtime.newFixnum(queue.getCurrentByteSize());
        }

        @JRubyMethod(name = "acked_count")
        public IRubyObject ruby_acked_count(ThreadContext context) {
            return context.runtime.newFixnum(queue.getAckedCount());
        }

        @JRubyMethod(name = "unread_count")
        public IRubyObject ruby_unread_count(ThreadContext context) {
            return context.runtime.newFixnum(queue.getUnreadCount());
        }

        @JRubyMethod(name = "unacked_count")
        public IRubyObject ruby_unacked_count(ThreadContext context) {
            return context.runtime.newFixnum(queue.getUnackedCount());
        }

        @JRubyMethod(name = "open")
        public IRubyObject ruby_open(ThreadContext context)
        {
            try {
                this.queue.getCheckpointIO().purge();
                this.queue.open();
            } catch (IOException e) {
                throw context.runtime.newIOErrorFromException(e);
            }

            return context.nil;
        }

        @JRubyMethod(name = {"write", "<<"}, required = 1)
        public IRubyObject ruby_write(ThreadContext context, IRubyObject event)
        {
            if (!(event instanceof JrubyEventExtLibrary.RubyEvent)) {
                throw context.runtime.newTypeError("wrong argument type " + event.getMetaClass() + " (expected LogStash::Event)");
            }

            long seqNum;
            try {
                seqNum = this.queue.write(((JrubyEventExtLibrary.RubyEvent) event).getEvent());
            } catch (IOException e) {
                throw context.runtime.newIOErrorFromException(e);
            }

            return context.runtime.newFixnum(seqNum);
        }

        @JRubyMethod(name = "read_batch", required = 2)
        public IRubyObject ruby_read_batch(ThreadContext context, IRubyObject limit, IRubyObject timeout)
        {
            Batch b;

            try {
                b = this.queue.readBatch(RubyFixnum.num2int(limit), RubyFixnum.num2int(timeout));
            } catch (IOException e) {
                throw context.runtime.newIOErrorFromException(e);
            }

            // TODO: return proper Batch object
            return (b == null) ? context.nil : new JrubyAckedBatchExtLibrary.RubyAckedBatch(context.runtime, b);
        }

        @JRubyMethod(name = "is_fully_acked?")
        public IRubyObject ruby_is_fully_acked(ThreadContext context)
        {
            return RubyBoolean.newBoolean(context.runtime, this.queue.isFullyAcked());
        }

        @JRubyMethod(name = "close")
        public IRubyObject ruby_close(ThreadContext context)
        {
            try {
                this.queue.close();
            } catch (IOException e) {
                throw context.runtime.newIOErrorFromException(e);
            }

            return context.nil;
        }

    }
}
