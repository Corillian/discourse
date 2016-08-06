require "uri"
require_dependency "file_store/base_store"
require_dependency "file_store/local_store"
require_dependency "file_helper"

require "azure"

module FileStore

  class AzureStore < BaseStore

    def store_upload(file, upload, content_type = nil)
      path = get_path_for_upload(upload)
      store_file(file, path, filename: upload.original_filename, content_type: content_type, cache_locally: true)
    end

    def store_file(file, path, opts={})
      # if this fails, it will throw an exception
      # upload(file, path, filename, content_type)

      filename      = opts[:filename].presence
      content_type  = opts[:content_type].presence

      if filename == nil
        filename = File.basename(path)
      end

      # cache file locally when needed
      cache_file(file, File.basename(path)) if opts[:cache_locally]
      
      # stored uploaded are public by default
      metadata = { }
      
      # add a "content disposition" header for "attachments"
      metadata[:content_disposition] = "attachment; filename=\"#{filename}\"" if filename
      
      # create azure options
      options = { :metadata => metadata }

      # add a "content type" header when provided
      if content_type
        options[:content_type] = content_type
      else
        options[:content_type] = get_content_type(filename)
      end

      # upload file
      get_or_create_directory(azure_container).create_block_blob(azure_container, path, file.read(), options)

      # url
      "#{absolute_base_url}/#{path}"
    end

    def remove_file(url)
      return unless has_been_uploaded?(url)
      filename = File.basename(url)
      remove(filename)
    end

    def has_been_uploaded?(url)
      return false if url.blank?
      
      base_hostname = URI.parse(absolute_base_url).hostname
      return true if url[base_hostname]

      #return false if SiteSetting.s3_cdn_url.blank?
      #cdn_hostname = URI.parse(SiteSetting.s3_cdn_url || "").hostname
      #cdn_hostname.presence && url[cdn_hostname]

      false
    end

    def absolute_base_url
      "//#{azure_storage_account}.blob.core.windows.net/#{azure_container}"
    end

    def external?
      true
    end

    def path_for(upload)
      url = upload.try(:url)
      FileStore::LocalStore.new.path_for(upload) if url && url[/^\/[^\/]/]
    end

    private

    def azure_container
      SiteSetting.azure_blob_container.downcase
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
      raise Discourse::SiteSettingMissing.new("azure_blob_container")      if SiteSetting.azure_blob_container.blank?
      raise Discourse::SiteSettingMissing.new("azure_storage_account")     if SiteSetting.azure_storage_account.blank?
      raise Discourse::SiteSettingMissing.new("azure_storage_access_key")  if SiteSetting.azure_storage_access_key.blank?

      load_azure_settings()
    end

    def get_or_create_directory(container)
      check_missing_site_settings()

      # NOTE: An Azure.blobs object MUST be created before a call to Azure::BlobService.new
      blobs = Azure.blobs

      begin
        blobs.create_container(container, { :public_access_level => "blob" })
      rescue Exception => e
        # NOTE: If the container already exists an exception will be thrown
        # so eat it
        # Rails.logger.warn(e.message)
      end

      Azure::BlobService.new
    end

    def remove(unique_filename)
      check_missing_site_settings()

      # NOTE: An Azure.blobs object MUST be created before a call to Azure::BlobService.new
      blobs = Azure.blobs

      begin
        azure_blob_service = Azure::BlobService.new
        azure_blob_service.delete_blob(azure_container, unique_filename)
      rescue Exception => e
        Rails.logger.error(e.message)
      end
    end
    
    def get_content_type(filename)
      ext = File.extname(filename) if filename != nil
      content_type = "application/octet-stream"

      if ext != nil
        ext = ext.downcase

        if ext == ".png"
          content_type = "image/png"
        elsif ext == ".jpg" || ext == ".jpeg" || ext == ".jfif"
          content_type = "image/jpeg"
        elsif ext == ".gif"
          content_type = "image/gif"
        elsif ext == ".tiff"
          content_type = "image/tiff"
        end
      end

      content_type
    end
  end
end