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


package org.logstash.instrument.monitors;

import com.sun.management.UnixOperatingSystemMXBean;
import java.lang.management.ManagementFactory;
import java.lang.management.OperatingSystemMXBean;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.TimeUnit;
import javax.management.MBeanServer;

public class ProcessMonitor {
    private static final OperatingSystemMXBean osMxBean = ManagementFactory.getOperatingSystemMXBean();
    private static final MBeanServer platformMxBean = ManagementFactory.getPlatformMBeanServer();

    public static class Report {
        private long memTotalVirtualInBytes = -1;
        private short cpuSystemPercent = -4;
        private short cpuProcessPercent = -3;
        private long cpuMillisTotal = -1;
        private boolean isUnix;
        private long openFds = -1;
        private long maxFds = -1;

        private Map<String, Object> map = new HashMap<>();

        Report() {
            this.isUnix = osMxBean instanceof UnixOperatingSystemMXBean;
            // Defaults are -1
            if (this.isUnix) {
                UnixOperatingSystemMXBean unixOsBean = (UnixOperatingSystemMXBean) osMxBean;;

                this.openFds = unixOsBean.getOpenFileDescriptorCount();
                this.maxFds =  unixOsBean.getMaxFileDescriptorCount();
                this.cpuMillisTotal = TimeUnit.MILLISECONDS.convert(
                    unixOsBean.getProcessCpuTime(), TimeUnit.NANOSECONDS
                );
                this.cpuProcessPercent = scaleLoadToPercent(unixOsBean.getProcessCpuLoad());
                this.cpuSystemPercent = scaleLoadToPercent(unixOsBean.getSystemCpuLoad());

                this.memTotalVirtualInBytes = unixOsBean.getCommittedVirtualMemorySize();
            }
        }

        public Map<String, Object> toMap() {
            map.put("open_file_descriptors", this.openFds);
            map.put("max_file_descriptors", this.maxFds);
            map.put("is_unix", this.isUnix);

            Map<String, Object> cpuMap = new HashMap<>();
            map.put("cpu", cpuMap);
            cpuMap.put("total_in_millis", this.cpuMillisTotal);
            cpuMap.put("process_percent", this.cpuProcessPercent);
            cpuMap.put("system_percent", this.cpuSystemPercent);

            Map<String, Object> memoryMap = new HashMap<>();
            map.put("mem", memoryMap);
            memoryMap.put("total_virtual_in_bytes", this.memTotalVirtualInBytes);

            return map;
        }

        private static short scaleLoadToPercent(double load) {
            if (osMxBean instanceof UnixOperatingSystemMXBean) {
                if (load >= 0) {
                    return (short) (load * 100);
                } else {
                    return -1;
                }
            } else {
                return -1;
            }
        }
    }

    public static Report detect() {
        return new Report();
    }
}
