require File.join(File.dirname(__FILE__), "helpers")
require "sensu/settings/loader"

describe "Sensu::Settings::Loader" do
  include Helpers

  before do
    @loader = Sensu::Settings::Loader.new
    @assets_dir = File.join(File.dirname(__FILE__), "assets")
    @config_file = File.join(@assets_dir, "config.json")
    @config_dir = File.join(@assets_dir, "conf.d")
  end

  it "can provide a loader API" do
    expect(@loader).to respond_to(:load_env, :load_file, :load_directory, :set_env!, :validate)
  end

  it "can provide indifferent access to settings" do
    expect(@loader[:checks]).to be_kind_of(Hash)
    expect(@loader["checks"]).to be_kind_of(Hash)
  end

  it "can validate loaded settings" do
    failures = @loader.validate
    expect(failures.size).to eq(0)
  end

  it "can load RabbitMQ settings from the environment" do
    ENV["RABBITMQ_URL"] = "amqp://guest:guest@localhost:5672/"
    @loader.load_env
    expect(@loader.warnings.size).to eq(1)
    ENV["RABBITMQ_URL"] = nil
  end

  it "can load Redis settings from the environment" do
    ENV["REDIS_URL"] = "redis://username:password@localhost:6789"
    @loader.load_env
    expect(@loader.warnings.size).to eq(1)
    ENV["REDIS_URL"] = nil
  end

  it "can load Sensu API settings from the environment" do
    ENV["API_PORT"] = "4567"
    @loader.load_env
    expect(@loader.warnings.size).to eq(1)
    ENV["API_PORT"] = nil
  end

  it "can load Redis and Sensu API settings from the environment using alternative variables" do
    ENV["REDISTOGO_URL"] = "redis://username:password@localhost:6789"
    ENV["PORT"] = "4567"
    @loader.load_env
    expect(@loader.warnings.size).to eq(2)
    ENV["REDISTOGO_URL"] = nil
    ENV["PORT"] = nil
  end

  it "can load settings from a file" do
    @loader.load_file(@config_file)
    expect(@loader.warnings.size).to eq(1)
    warning = @loader.warnings.first
    expect(warning[:file]).to eq(File.expand_path(@config_file))
    expect(warning[:message]).to eq("loading config file")
    expect(@loader[:api][:port]).to eq(4567)
    expect(@loader["api"]["port"]).to eq(4567)
  end

  it "can load settings from a file and validate them" do
    @loader.load_file(@config_file)
    failures = @loader.validate
    reasons = failures.map do |failure|
      failure[:message]
    end
    expect(reasons).to include("check interval must be an integer")
  end

  it "can attempt to load settings from a nonexistent file" do
    @loader.load_file("/tmp/bananaphone")
    warnings = @loader.warnings
    expect(warnings.size).to eq(2)
    messages = warnings.map do |warning|
      warning[:message]
    end
    expect(messages).to include("config file does not exist or is not readable")
    expect(messages).to include("ignoring config file")
  end

  it "can attempt to load settings from a file with invalid JSON" do
    @loader.load_file(File.join(@assets_dir, "invalid.json"))
    warnings = @loader.warnings
    expect(warnings.size).to eq(3)
    messages = warnings.map do |warning|
      warning[:message]
    end
    expect(messages).to include("loading config file")
    expect(messages).to include("config file must be valid json")
    expect(messages).to include("ignoring config file")
  end

  it "can load settings from files in a directory" do
    @loader.load_directory(@config_dir)
    warnings = @loader.warnings
    expect(warnings.size).to eq(4)
    messages = warnings.map do |warning|
      warning[:message]
    end
    expect(messages).to include("loading config files from directory")
    expect(messages).to include("loading config file")
    expect(messages).to include("config file applied changes")
    expect(@loader[:checks][:nested][:command]).to eq("true")
  end

  it "can attempt to load settings from files in a nonexistent directory" do
    @loader.load_directory("/tmp/rottentomatos")
    expect(@loader.warnings.size).to eq(1)
    warning = @loader.warnings.first
    expect(warning[:message]).to eq("loading config files from directory")
  end

  it "can set environment variables for child processes" do
    @loader.load_file(@config_file)
    @loader.load_directory(@config_dir)
    expect(@loader.loaded_files.size).to eq(3)
    @loader.set_env!
    expect(ENV["SENSU_CONFIG_FILES"].split(":")).to eq(@loader.loaded_files)
  end

  it "can load settings and determine if certain definitions exist" do
    @loader.load_file(@config_file)
    @loader.load_directory(@config_dir)
    expect(@loader.check_exists?("nonexistent")).to be(false)
    expect(@loader.check_exists?("tokens")).to be(true)
    expect(@loader.filter_exists?("nonexistent")).to be(false)
    expect(@loader.filter_exists?("development")).to be(true)
    expect(@loader.mutator_exists?("nonexistent")).to be(false)
    expect(@loader.mutator_exists?("noop")).to be(true)
    expect(@loader.handler_exists?("nonexistent")).to be(false)
    expect(@loader.handler_exists?("default")).to be(true)
  end

  it "can load settings and provide setting category accessors" do
    @loader.load_file(@config_file)
    @loader.load_directory(@config_dir)
    expect(@loader.checks).to be_kind_of(Array)
    expect(@loader.checks).to_not be_empty
    check = @loader.checks.detect do |check|
      check[:name] == "tokens"
    end
    expect(check[:interval]).to eq(1)
    expect(@loader.filters).to be_kind_of(Array)
    expect(@loader.filters).to_not be_empty
    filter = @loader.filters.detect do |filter|
      filter[:name] == "development"
    end
    expect(filter[:negate]).to be(true)
    expect(@loader.mutators).to be_kind_of(Array)
    expect(@loader.mutators).to_not be_empty
    mutator = @loader.mutators.detect do |mutator|
      mutator[:name] == "noop"
    end
    expect(mutator[:command]).to eq("cat")
    expect(@loader.handlers).to be_kind_of(Array)
    expect(@loader.handlers).to_not be_empty
    handler = @loader.handlers.detect do |handler|
      handler[:name] == "default"
    end
    expect(handler[:type]).to eq("set")
  end
end
