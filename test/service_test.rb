require_relative "test_helper"

class ServiceTest < Minitest::Test
  J = JackAndTheElasticBeanstalk

  def test_archive
    tmpdir do |path|
      (path + "foo.txt").write "foo"
      (path + "dir").mkdir
      (path + "dir/file1").write "file1"
      (path + "dir/.hidden").write ".hidden"
      (path + ".ebextension").mkdir
      (path + ".ebextension/config.yml").write "config"

      service = J::Service.new(config: nil, source_dir: nil, eb: nil, runner: nil, logger: nil)

      tmpdir do |output_dir|
        output_path = output_dir + "foo.zip"

        service.archive(input_dir: path, output_path: output_path)

        assert output_path.file?

        Zip::File.open(output_path.to_s) do |zip|
          assert zip.find_entry("foo.txt")
          assert zip.find_entry("dir/file1")
          assert zip.find_entry(".ebextension/config.yml")
          assert zip.find_entry("dir/.hidden")
        end
      end
    end
  end
end
