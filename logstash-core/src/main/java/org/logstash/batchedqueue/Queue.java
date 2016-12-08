package org.logstash.batchedqueue;

import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.locks.Condition;
import java.util.concurrent.locks.Lock;
import java.util.concurrent.locks.ReentrantLock;

public class Queue<E> {

    // thread safety
    final Lock lock = new ReentrantLock();
    final Condition notFull  = lock.newCondition();
    final Condition notEmpty = lock.newCondition();

    final int limit;
    private List batch;

    public Queue(int limit) {
        this.limit = limit;
        this.batch = new ArrayList<E>();
    }

    public void write(E element) {
        lock.lock();
        try {

            // empty queue shortcut
            if (this.batch.isEmpty()) {
                this.batch.add(element);
                notEmpty.signal();
                return;
            }

            while (isFull()) {
                try {
                    notFull.await();
                } catch (InterruptedException e) {
                    // the thread interrupt() has been called while in the await() blocking call.
                    // at this point the interrupted flag is reset and Thread.interrupted() will return false
                    // to any upstream calls on it. for now our choice is to return normally and set back
                    // the Thread.interrupted() flag so it can be checked upstream.

                    // set back the interrupted flag
                    Thread.currentThread().interrupt();

                    return;
                }
            }

            this.batch.add(element);
        } finally {
            lock.unlock();
        }
    }

    public boolean isFull() {
        return this.batch.size() >= this.limit;
    }

    public boolean isEmpty() {
        lock.lock();
        try {
            return this.batch.isEmpty();
        } finally {
            lock.unlock();
        }
    }

    public List<E> nonBlockReadBatch() {
        lock.lock();
        try {
            // full queue shortcut
            if (isFull()) {
                List<E> batch = swap();
                notFull.signal();
                return batch;
            }

            if (this.batch.isEmpty()) { return null; }

            return swap();
        } finally {
            lock.unlock();
        }
    }

    public List<E> readBatch() {
        return null;
    }

    public List<E> readBatch(long timeout) {
        lock.lock();
        try {
            while (this.batch.isEmpty()) {
                try {
                    if (!notEmpty.await(timeout, TimeUnit.MILLISECONDS)) {
                        // await return false when reaching timeout
                        break;
                    }
                } catch (InterruptedException e) {
                    // the thread interrupt() has been called while in the await() blocking call.
                    // at this point the interrupted flag is reset and Thread.interrupted() will return false
                    // to any upstream calls on it. for now our choice is to simply return null and set back
                    // the Thread.interrupted() flag so it can be checked upstream.

                    // set back the interrupted flag
                    Thread.currentThread().interrupt();

                    return null;
                }
            }

            if (this.batch.isEmpty()) { return null; }

            if (isFull()) {
                List<E> batch = swap();
                notFull.signal();
                return batch;
            }

            return swap();
        } finally {
            lock.unlock();
        }
    }

    public void close() {
        // nothing
    }


    private List<E> swap() {
        List<E> batch = this.batch;
        this.batch = new ArrayList<>();
        return batch;
    }

}