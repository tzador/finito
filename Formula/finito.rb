class Finito < Formula
  desc "Blow autumn leaves across all your displays from the command-line"
  homepage "https://github.com/tzador/finito"
  url "https://github.com/tzador/finito/archive/refs/tags/v0.5.0.tar.gz"
  sha256 "0f99127456ebda8523bac753f2385ab88f16ce914aaa6207c48b7b1f08f801eb"
  license "MIT"
  head "https://github.com/tzador/finito.git", branch: "main"

  depends_on "rust" => :build
  depends_on macos: :ventura

  def install
    system "cargo", "install", *std_cargo_args
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/finito --version")
  end
end
