require 'azure'

class Backup
  include UrlHelper
  include ActiveModel::SerializerSupport

  attr_reader :filename
  attr_accessor :size, :path, :link

  def initialize(filename)
    @filename = filename
  end

  def self.all
    backups = Dir.glob(File.join(Backup.base_directory, "*.tar.gz"))
    backups.sort.reverse.map { |backup| Backup.create_from_filename(File.basename(backup)) }
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
    upload_to_azure if SiteSetting.enable_azure_backups?
  end

  def after_remove_hook
    remove_from_s3 if SiteSetting.enable_s3_backups?
    remove_from_azure if SiteSetting.enable_azure_backups?
  end

  def upload_to_s3
    return unless fog_directory
    fog_directory.files.create(key: @filename, public: false, body: File.read(@path))
  end

  def remove_from_s3
    return unless fog
    fog.delete_object(SiteSetting.s3_backup_bucket, @filename)
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
      b.link = b.schemaless "#{Discourse.base_url}/admin/backups/#{b.filename}"
      b.size = File.size(b.path)
    end
  end

  def self.remove_old
    all_backups = Backup.all
    return unless all_backups.size > SiteSetting.maximum_backups
    all_backups[SiteSetting.maximum_backups..-1].each {|b| b.remove}
  end

  def upload_to_azure
    get_or_create_directory(azure_container).create_block_blob(azure_container, @filename, File.read(@path), {})
  end

  def remove_from_azure
    check_missing_site_settings()
    azure_blob_service = Azure::BlobService.new
    azure_blob_service.delete_blob(azure_container, @filename)
  end

  def azure_container
      SiteSetting.azure_backup_container.downcase
  end

  def azure_storage_account
    SiteSetting.azure_storage_account.downcase
  end

  def load_azure_settings
    Azure.configure do |config|
      config.storage_account_name = azure_storage_account
      config.storage_access_key   = SiteSetting.azure_storage_access_key
    end
  end

  def check_missing_site_settings
    raise Discourse::SiteSettingMissing.new("azure_backup_container")     if SiteSetting.azure_backup_container.blank?
    raise Discourse::SiteSettingMissing.new("azure_storage_account")     if SiteSetting.azure_storage_account.blank?
    raise Discourse::SiteSettingMissing.new("azure_storage_access_key") if SiteSetting.azure_storage_access_key.blank?

    load_azure_settings()
  end

  def get_or_create_azure_directory(container)
    check_missing_site_settings()

    azure_blob_service = Azure::BlobService.new

    begin
      # NOTE: No options which specifies it's a private blob
      azure_blob_service.create_container(container, {})
    rescue Exception => e
      # NOTE: If the container already exists an exception will be thrown
      # so eat it
      Rails.logger.warn(e.message)
    end

    azure_blob_service
  end

  private

    def fog
      return @fog if @fog
      return unless SiteSetting.s3_access_key_id.present? &&
                    SiteSetting.s3_secret_access_key.present? &&
                    SiteSetting.s3_backup_bucket.present?
      require 'fog'
      @fog = Fog::Storage.new(provider: 'AWS',
                              aws_access_key_id: SiteSetting.s3_access_key_id,
                              aws_secret_access_key: SiteSetting.s3_secret_access_key)
    end

    def fog_directory
      return @fog_directory if @fog_directory
      return unless fog
      @fog_directory ||= fog.directories.get(SiteSetting.s3_backup_bucket)
    end

end
