class Mesos < Formula
  desc "Apache cluster manager"
  homepage "https://mesos.apache.org"
  url "https://www.apache.org/dyn/closer.cgi?path=mesos/1.1.0/mesos-1.1.0.tar.gz"
  mirror "https://archive.apache.org/dist/mesos/1.1.0/mesos-1.1.0.tar.gz"
  sha256 "0f6d591eff78483e07bee93aed4553c69064f7870b216817a0085def3569b2c1"

  bottle do
    rebuild 1
    sha256 "e1dbeb8e89b87dee7418383ed334c42c4c67256e5c417377de353f733a90a1b6" => :sierra
    sha256 "cbbe747db8970900494a9be4944d3a1b4c378a54819bb3fcead5fdc9e4efe25f" => :el_capitan
    sha256 "5ad291f41511fcf9a1644a032bff98b2d445178723b433f698084b62bdba592b" => :yosemite
  end

  depends_on :java => "1.7+"
  depends_on :macos => :mountain_lion
  depends_on "apr-util" => :build
  depends_on "maven" => :build
  depends_on "subversion"

  resource "protobuf" do
    url "https://pypi.python.org/packages/source/p/protobuf/protobuf-2.6.1.tar.gz"
    sha256 "8faca1fb462ee1be58d00f5efb4ca4f64bde92187fe61fde32615bbee7b3e745"
  end

  # build dependencies for protobuf
  resource "six" do
    url "https://files.pythonhosted.org/packages/b3/b2/238e2590826bfdd113244a40d9d3eb26918bd798fc187e2360a8367068db/six-1.10.0.tar.gz"
    sha256 "105f8d68616f8248e24bf0e9372ef04d3cc10104f1980f54d57b2ce73a5ad56a"
  end

  resource "python-dateutil" do
    url "https://files.pythonhosted.org/packages/3e/f5/aad82824b369332a676a90a8c0d1e608b17e740bbb6aeeebca726f17b902/python-dateutil-2.5.3.tar.gz"
    sha256 "1408fdb07c6a1fa9997567ce3fcee6a337b39a503d80699e0f213de4aa4b32ed"
  end

  resource "pytz" do
    url "https://files.pythonhosted.org/packages/f7/c7/08e54702c74baf9d8f92d0bc331ecabf6d66a56f6d36370f0a672fc6a535/pytz-2016.6.1.tar.bz2"
    sha256 "b5aff44126cf828537581e534cc94299b223b945a2bb3b5434d37bf8c7f3a10c"
  end

  resource "python-gflags" do
    url "https://files.pythonhosted.org/packages/6b/1c/47996c14dc91249376f218c0f943da3b85ff7e9af9c5de05cd2600c8afb4/python-gflags-3.0.7.tar.gz"
    sha256 "db889af55e39fa6a37125d6aa70dfdd788dbc180f9566d3053250e28877e68dc"
  end

  resource "google-apputils" do
    url "https://files.pythonhosted.org/packages/69/66/a511c428fef8591c5adfa432a257a333e0d14184b6c5d03f1450827f7fe7/google-apputils-0.4.2.tar.gz"
    sha256 "47959d0651c32102c10ad919b8a0ffe0ae85f44b8457ddcf2bdc0358fb03dc29"
  end

  needs :cxx11

  def install
    ENV.java_cache

    # Disable optimizing as libc++ does not play well with optimized clang
    # builds (see https://llvm.org/bugs/show_bug.cgi?id=28469 and
    # https://issues.apache.org/jira/browse/MESOS-5745).
    #
    # NOTE: We cannot use `--disable-optimize` since we also pass e.g.,
    # CXXFLAGS via environment variables. Since compiler flags are passed via
    # environment variables the Mesos build will silently ignore flags like
    # `--[disable|enable]-optimize`.
    ENV.O0 unless DevelopmentTools.clang_build_version >= 900

    # work around to avoid `_clock_gettime` symbol not found error.
    if MacOS.version == "10.11" && MacOS::Xcode.installed? && MacOS::Xcode.version >= "8.0"
      ENV["ac_have_clock_syscall"] = "no"
    end

    # work around distutils abusing CC instead of using CXX
    # https://issues.apache.org/jira/browse/MESOS-799
    # https://github.com/Homebrew/homebrew/pull/37087
    native_patch = <<-EOS.undent
      import os
      os.environ["CC"] = os.environ["CXX"]
      os.environ["LDFLAGS"] = "@LIBS@"
      \\0
    EOS
    inreplace "src/python/executor/setup.py.in",
              "import ext_modules",
              native_patch

    inreplace "src/python/scheduler/setup.py.in",
              "import ext_modules",
              native_patch

    # skip build javadoc because Homebrew sandbox ENV.java_cache
    # would trigger maven-javadoc-plugin bug.
    # https://issues.apache.org/jira/browse/MESOS-3482
    maven_javadoc_patch = <<-EOS.undent
      <properties>
        <maven.javadoc.skip>true</maven.javadoc.skip>
      </properties>
      \\0
    EOS
    inreplace "src/java/mesos.pom.in",
              "<url>http://mesos.apache.org</url>",
              maven_javadoc_patch

    args = %W[
      --prefix=#{prefix}
      --disable-debug
      --disable-dependency-tracking
      --disable-silent-rules
      --with-svn=#{Formula["subversion"].opt_prefix}
    ]

    unless MacOS::CLT.installed?
      args << "--with-apr=#{Formula["apr-util"].opt_libexec}"
    end

    ENV.cxx11

    system "./configure", "--disable-python", *args
    system "make"
    system "make", "install"

    # The native Python modules `executor` and `scheduler` (see below) fail to
    # link to Subversion libraries if Homebrew isn't installed in `/usr/local`.
    ENV.append_to_cflags "-L#{Formula["subversion"].opt_lib}"

    system "./configure", "--enable-python", *args
    ["native", "interface", "executor", "scheduler", "cli", ""].each do |p|
      cd "src/python/#{p}" do
        system "python", *Language::Python.setup_install_args(prefix)
      end
    end

    # stage protobuf build dependencies
    ENV.prepend_create_path "PYTHONPATH", buildpath/"protobuf/lib/python2.7/site-packages"
    %w[six python-dateutil pytz python-gflags google-apputils].each do |r|
      resource(r).stage do
        system "python", *Language::Python.setup_install_args(buildpath/"protobuf")
      end
    end

    protobuf_path = libexec/"protobuf/lib/python2.7/site-packages"
    ENV.prepend_create_path "PYTHONPATH", protobuf_path
    resource("protobuf").stage do
      ln_s buildpath/"protobuf/lib/python2.7/site-packages/google/apputils", "google/apputils"
      system "python", *Language::Python.setup_install_args(libexec/"protobuf")
    end
    pth_contents = "import site; site.addsitedir('#{protobuf_path}')\n"
    (lib/"python2.7/site-packages/homebrew-mesos-protobuf.pth").write pth_contents
  end

  test do
    require "timeout"

    # Make sure we are not affected by MESOS-6910 and related issues.
    agent = fork do
      exec "/Users/bbannier/src/homebrew/sbin/mesos-agent",
          "--master=127.0.0.1:5050",
          "--work_dir=/tmp/mesos.slave.brew",
          "--image_providers=docker"
    end
    begin
      Timeout.timeout(2) do
        Process.wait agent
      end
    rescue Timeout::Error
      Process.kill "TERM", agent
    end
    assert $?.exitstatus, "agent process died, check MESOS-6606-related behavior"

    # Make tests for minimal functionality.
    master = fork do
      exec "#{sbin}/mesos-master", "--ip=127.0.0.1",
                                   "--registry=in_memory"
    end
    agent = fork do
      exec "#{sbin}/mesos-agent", "--master=127.0.0.1:5050",
                                  "--work_dir=#{testpath}"
    end
    Timeout.timeout(15) do
      system "#{bin}/mesos", "execute",
                             "--master=127.0.0.1:5050",
                             "--name=execute-touch",
                             "--command=touch\s#{testpath}/executed"
    end
    Process.kill("TERM", master)
    Process.kill("TERM", agent)
    assert File.exist?("#{testpath}/executed")
    system "python", "-c", "import mesos.native"
  end
end
