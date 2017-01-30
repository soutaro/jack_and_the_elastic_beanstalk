require_relative "test_helper"

class ConfigTest < Minitest::Test
  def test_s3_bucket
    config = JEB::Config.new(app_hash: { "s3_bucket" => "some.bucket.name" }, eb_configs: [])

    assert_equal "some.bucket.name", config.s3_bucket
  end
end
