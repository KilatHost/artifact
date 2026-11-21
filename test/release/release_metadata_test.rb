require "test_helper"

class ReleaseMetadataTest < ActiveSupport::TestCase
  ROOT = Rails.root

  test "version is semantic" do
    assert_match(/\A\d+\.\d+\.\d+\z/, KilatArtifact::VERSION)
  end

  test "compose and env example default to the current release image" do
    compose = ROOT.join("compose.yaml").read
    assert_equal 2, compose.scan("image: ${ARTIFACT_IMAGE:-ghcr.io/kilathost/artifact}:${ARTIFACT_VERSION:-#{KilatArtifact::VERSION}}").size
    assert_includes ROOT.join(".env.example").read.lines.map(&:strip), "ARTIFACT_VERSION=#{KilatArtifact::VERSION}"
  end

  test "changelog has an entry for the current version" do
    assert_match(/^## \[#{Regexp.escape(KilatArtifact::VERSION)}\] - (\d{4}-\d{2}-\d{2}|Unreleased)$/, ROOT.join("CHANGELOG.md").read)
  end
end
