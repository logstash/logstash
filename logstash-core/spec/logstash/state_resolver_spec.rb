# Licensed to Elasticsearch B.V. under one or more contributor
# license agreements. See the NOTICE file distributed with
# this work for additional information regarding copyright
# ownership. Elasticsearch B.V. licenses this file to you under
# the Apache License, Version 2.0 (the "License"); you may
# not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#  http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.

require "spec_helper"
require_relative "../support/helpers"
require_relative "../support/matchers"
require "logstash/state_resolver"
require "logstash/config/pipeline_config"
require "logstash/pipeline"
require "ostruct"
require "digest"

describe LogStash::StateResolver do
  subject { described_class.new(metric) }
  let(:metric) { LogStash::Instrument::NullMetric.new }

  before do
    clear_data_dir
  end

  after do
    # ensure that the the created pipeline are closed
    pipelines.running_pipelines.each { |_, pipeline| pipeline.close }
  end

  context "when no pipeline is running" do
    let(:pipelines) {  LogStash::PipelinesRegistry.new }

    context "no pipeline configs is received" do
      let(:pipeline_configs) { [] }

      it "returns no action" do
        expect(subject.resolve(pipelines, pipeline_configs).size).to eq(0)
      end
    end

    context "we receive some pipeline configs" do
      let(:pipeline_configs) { [mock_pipeline_config(:hello_world)] }

      it "returns some actions" do
        expect(subject.resolve(pipelines, pipeline_configs)).to have_actions(
          [:create, :hello_world],
        )
      end
    end
  end

  context "when some pipeline are running" do
    context "when a pipeline is running" do
      let(:main_pipeline) { mock_pipeline(:main) }
      let(:main_pipeline_config) { main_pipeline.pipeline_config }
      let(:pipelines) do
        r =  LogStash::PipelinesRegistry.new
        r.create_pipeline(:main, main_pipeline) { true }
        r
      end

      context "when the pipeline config contains a new one and the existing" do
        let(:pipeline_configs) { [mock_pipeline_config(:hello_world), main_pipeline_config ] }

        it "creates the new one and keep the other one" do
          expect(subject.resolve(pipelines, pipeline_configs)).to have_actions(
            [:create, :hello_world],
          )
        end

        context "when the pipeline config contains only the new one" do
          let(:pipeline_configs) { [mock_pipeline_config(:hello_world)] }

          it "creates the new one and stop the old one one" do
            expect(subject.resolve(pipelines, pipeline_configs)).to have_actions(
              [:create, :hello_world],
              [:stop, :main]
            )
          end
        end

        context "when the pipeline config contains no pipeline" do
          let(:pipeline_configs) { [] }

          it "stops the old one one" do
            expect(subject.resolve(pipelines, pipeline_configs)).to have_actions(
              [:stop, :main]
            )
          end
        end

        context "when pipeline config contains an updated pipeline" do
          let(:pipeline_configs) { [mock_pipeline_config(:main, "input { generator {}}")] }

          it "reloads the old one one" do
            expect(subject.resolve(pipelines, pipeline_configs)).to have_actions(
              [:reload, :main]
            )
          end
        end
      end
    end

    context "when we have a lot of pipeline running" do
      let(:pipelines) do
        r =  LogStash::PipelinesRegistry.new
        r.create_pipeline(:main1, mock_pipeline(:main1)) { true }
        r.create_pipeline(:main2, mock_pipeline(:main2)) { true }
        r.create_pipeline(:main3, mock_pipeline(:main3)) { true }
        r.create_pipeline(:main4, mock_pipeline(:main4)) { true }
        r.create_pipeline(:main5, mock_pipeline(:main5)) { true }
        r.create_pipeline(:main6, mock_pipeline(:main6)) { true }
        r
      end

      context "without system pipeline" do
        let(:pipeline_configs) do
          [
            pipelines.get_pipeline(:main1).pipeline_config,
            mock_pipeline_config(:main9),
            mock_pipeline_config(:main5, "input { generator {}}"),
            mock_pipeline_config(:main3, "input { generator {}}"),
            mock_pipeline_config(:main7)
          ]
        end

        it "generates actions required to converge" do
          expect(subject.resolve(pipelines, pipeline_configs)).to have_actions(
            [:create, :main7],
            [:create, :main9],
            [:reload, :main3],
            [:reload, :main5],
            [:stop, :main2],
            [:stop, :main4],
            [:stop, :main6]
          )
        end
      end

      context "with system pipeline" do
        let(:pipeline_configs) do
          [
            pipelines.get_pipeline(:main1).pipeline_config,
            mock_pipeline_config(:main9),
            mock_pipeline_config(:main5, "input { generator {}}"),
            mock_pipeline_config(:main3, "input { generator {}}"),
            mock_pipeline_config(:main7),
            mock_pipeline_config(:monitoring, "input { generator {}}", { "pipeline.system" => true }),
          ]
        end

        it "creates the system pipeline before user defined pipelines" do
          expect(subject.resolve(pipelines, pipeline_configs)).to have_actions(
            [:create, :monitoring],
            [:create, :main7],
            [:create, :main9],
            [:reload, :main3],
            [:reload, :main5],
            [:stop, :main2],
            [:stop, :main4],
            [:stop, :main6]
          )
        end
      end
    end
  end
end
