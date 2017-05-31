# encoding: utf-8
require "spec_helper"
require "logstash/plugins/registry"
require "logstash/inputs/base"

# use a dummy NOOP input to test plugin registry
class LogStash::Inputs::Dummy < LogStash::Inputs::Base
  config_name "dummy"

  def register; end
end


class LogStash::Inputs::NewPlugin < LogStash::Inputs::Base
  config_name "new_plugin"

  def register; end
end

describe LogStash::Plugins::Registry do
  let(:registry) { described_class.new }

  context "when loading installed plugins" do
    let(:plugin) { double("plugin") }

    it "should return the expected class" do
      klass = registry.lookup("input", "stdin")
      expect(klass).to eq(LogStash::Inputs::Stdin)
    end

    it "should raise an error if can not find the plugin class" do
      expect { registry.lookup("input", "do-not-exist-elastic") }.to raise_error(LoadError)
    end

    it "should load from registry is already load" do
      expect(registry.exists?(:input, "stdin")).to be_falsey
      expect { registry.lookup("input", "new_plugin") }.to change { registry.size }.by(1)
      expect { registry.lookup("input", "new_plugin") }.not_to change { registry.size }
    end
  end

  context "when loading code defined plugins" do
    it "should return the expected class" do
      klass = registry.lookup("input", "dummy")
      expect(klass).to eq(LogStash::Inputs::Dummy)
    end
  end

  context "when plugin is not installed and not defined" do
    it "should raise an error" do
      expect { registry.lookup("input", "elastic") }.to raise_error(LoadError)
    end
  end

  context "when loading plugin manually configured" do
    let(:simple_plugin) { Class.new }

    it "should return the plugin" do
      expect { registry.lookup("filter", "simple_plugin") }.to raise_error(LoadError)
      registry.add(:filter, "simple_plugin", simple_plugin)
      expect(registry.lookup("filter", "simple_plugin")).to eq(simple_plugin)
    end

    it "doesn't add multiple time the same plugin" do
      plugin1 = Class.new
      plugin2 = Class.new

      registry.add(:filter, "simple_plugin", plugin1)
      registry.add(:filter, "simple_plugin", plugin2)

      expect(registry.plugins_with_type(:filter)).to include(plugin1)
      expect(registry.plugins_with_type(:filter).size).to eq(1)
    end

    it "allow you find plugin by type" do
      registry.add(:filter, "simple_plugin", simple_plugin)

      expect(registry.plugins_with_type(:filter)).to include(simple_plugin)
      expect(registry.plugins_with_type(:modules)).to match([])
    end

    it "doesn't add multiple time the same plugin" do
      plugin1 = Class.new
      plugin2 = Class.new

      registry.add(:filter, "simple_plugin", plugin1)
      registry.add(:filter, "simple_plugin", plugin2)

      expect(registry.plugins_with_type(:filter)).to include(plugin1)
      expect(registry.plugins_with_type(:filter).size).to eq(1)
    end

    it "allow you find plugin by type" do
      registry.add(:filter, "simple_plugin", SimplePlugin)

      expect(registry.plugins_with_type(:filter)).to include(SimplePlugin)
      expect(registry.plugins_with_type(:modules)).to match([])
    end
  end
end
