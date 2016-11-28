require_relative "test_helper"

class ConfigTest < Minitest::Test
  def test_load
    config = JEB::Config.load(path: Pathname("foo/bar"))

  end
end
