require "azure"

class Backup
  include ActiveModel::SerializerSupport

  attr_reader :filename
  attr_accessor :size, :path, :link

  def initialize(filename)
    @filename = filename
  end

  def self.all
    Dir.glob(File.join(Backup.base_directory, "*.{gz,tgz}"))
       .sort_by { |file| File.mtime(file) }
       .reverse
       .map { |backup| Backup.create_from_filename(File.basename(backup)) }
  end

  def self.[](filename)
    path = File.join(Backup.base_directory, filename)
    if File.exists?(path)
      Backup.create_from_filename(filename)
    else
      nil
    end
  end

  def remove
    File.delete(@path) if File.exists?(path)
    after_remove_hook
  end

  def after_create_hook
    upload_to_s3 if SiteSetting.enable_s3_backups?
    upload_to_azure if SiteSEttings.enable_azure_backups?
  end

  def after_remove_hook
    remove_from_s3 if SiteSetting.enable_s3_backups?
    remove_from_azure if SiteSEttings.enable_azure_backups?
  end

  def s3_bucket
    return @s3_bucket if @s3_bucket
    raise Discourse::SiteSettingMissing.new("s3_backup_bucket") if SiteSetting.s3_backup_bucket.blank?
    @s3_bucket = SiteSetting.s3_backup_bucket.downcase
  end

  def s3
    require "s3_helper" unless defined? S3Helper
    @s3_helper ||= S3Helper.new(s3_bucket)
  end

  def upload_to_s3
    return unless s3
    File.open(@path) do |file|
      s3.upload(file, @filename)
    end
  end

  def remove_from_s3
    return unless s3
    s3.remove(@filename)
  end

  def load_azure_settings
    Azure.configure do |config|
      config.storage_account_name = azure_storage_account
      config.storage_access_key   = SiteSetting.azure_storage_access_key
    end
  end

  def check_missing_azure_site_settings
    raise Discourse::SiteSettingMissing.new("azure_backup_container")   if SiteSetting.azure_backup_container.blank?
    raise Discourse::SiteSettingMissing.new("azure_storage_account")    if SiteSetting.azure_storage_account.blank?
    raise Discourse::SiteSettingMissing.new("azure_storage_access_key") if SiteSetting.azure_storage_access_key.blank?

    load_azure_settings()
  end

  def azure_storage_account
    SiteSetting.azure_storage_account.downcase
  end

  def azure_container
    SiteSetting.azure_backup_container.downcase
  end

  def get_or_create_azure_directory(container)
    check_missing_azure_site_settings()

    azure_blob_service = Azure::BlobService.new

    begin
      azure_blob_service.create_container(container)
    rescue Exception => e
      # NOTE: If the container already exists an exception will be thrown
      # so eat it
      Rails.logger.warn(e.message)
    end

    azure_blob_service
  end

  def upload_to_azure
    content = File.open(@path, "rb") { |file| file.read }

    get_or_create_azure_directory(azure_container).create_block_blob(azure_container, @filename.downcase, content)
  end

  def remove_from_azure
    check_missing_azure_site_settings()
    azure_blob_service = Azure::BlobService.new
    azure_blob_service.delete_blob(azure_container, @filename.downcase)
  end

  def self.base_directory
    File.join(Rails.root, "public", "backups", RailsMultisite::ConnectionManagement.current_db)
  end

  def self.chunk_path(identifier, filename, chunk_number)
    File.join(Backup.base_directory, "tmp", identifier, "#{filename}.part#{chunk_number}")
  end

  def self.create_from_filename(filename)
    Backup.new(filename).tap do |b|
      b.path = File.join(Backup.base_directory, b.filename)
      b.link = UrlHelper.schemaless "#{Discourse.base_url}/admin/backups/#{b.filename}"
      b.size = File.size(b.path)
    end
  end

  def self.remove_old
    return if Rails.env.development?
    all_backups = Backup.all
    return if all_backups.size <= SiteSetting.maximum_backups
    all_backups[SiteSetting.maximum_backups..-1].each(&:remove)
  end

end
