$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)
$LOAD_PATH.unshift(File.dirname(__FILE__))

require 'rspec'
require 'zip_tricks'
require 'digest'
require 'fileutils'
require 'shellwords'
require 'zip'
require 'delegate'

class ReadMonitor < SimpleDelegator
  def read(*)
    super.tap { @num_reads ||= 0 
                @num_reads += 1 }
  end
  
  def num_reads
    @num_reads || 0
  end
end

module Keepalive
  # Travis-CI kills the build if it does not receive output on standard out or standard error
  # for longer than a few minutes. We have a few tests that take a _very_ long time, and during
  # those tests this method has to be called every now and then to revive the output and let the
  # build proceed.
  def still_alive!
    # Rubocop: convention: Do not introduce global variables.
    # Rubocop: convention: Use a guard clause instead of wrapping the code
    #          inside a conditional expression.
    $keepalive_last_out_ping_at ||= Time.now
    if (Time.now - $keepalive_last_out_ping_at) > 3
      $keepalive_last_out_ping_at = Time.now
      $stdout << '_'
    end
  end
  module_function :still_alive!
end

class ManagedTempfile < Tempfile
  # Rubocop: convention: Replace class var @@managed_tempfiles with a class instance var.
  @@managed_tempfiles = []
  
  def initialize(*)
    super
    @@managed_tempfiles << self
  end
  
  def self.prune!
    @@managed_tempfiles.each do |tf|
      # Rubocop: convention: Avoid using rescue in its modifier form.
      # Rubocop: convention: Do not use semicolons to terminate expressions.
      (tf.close; tf.unlink) rescue nil
    end
    @@managed_tempfiles.clear
  end
end

module ZipInspection
  def inspect_zip_with_external_tool(path_to_zip)
    zipinfo_path = 'zipinfo'
    # Rubocop: convention: Do not introduce global variables.
    $zip_inspection_buf ||= StringIO.new
    $zip_inspection_buf.puts "\n"
    # The only way to get at the RSpec example without using the block argument
    $zip_inspection_buf.puts "Inspecting ZIP output of #{inspect}." 
    $zip_inspection_buf.puts 'Be aware that the zipinfo version on OSX is too \ 
                              old to deal with Zip64.'
    escaped_cmd = Shellwords.join([zipinfo_path, '-tlhvz', path_to_zip])
    $zip_inspection_buf.puts `#{escaped_cmd}`
  end
  
  def open_with_external_app(app_path, path_to_zip, skip_if_missing)
    bin_exists = File.exist?(app_path)
    skip "This system does not have #{File.basename(app_path)}" if skip_if_missing && !bin_exists
    return unless bin_exists
    `#{Shellwords.join([app_path, path_to_zip])}`
  end
  
  def open_zip_with_archive_utility(path_to_zip, skip_if_missing: false)
    # ArchiveUtility sometimes puts the stuff it unarchives in ~/Downloads etc. so do
    # not perform any checks on the files since we do not really know where they are on disk.
    # Visual inspection should show whether the unarchiving is handled correctly.
    au_path = '/System/Library/CoreServices/Applications/Archive Utility.app/ \
              Contents/MacOS/Archive Utility'
    open_with_external_app(au_path, path_to_zip, skip_if_missing)
  end
end

RSpec.configure do |config|
  config.include Keepalive
  config.include ZipInspection
  
  config.after :each do
    ManagedTempfile.prune!
  end
  
  config.after :suite do
    $stderr << $zip_inspection_buf.string if $zip_inspection_buf
  end
end
