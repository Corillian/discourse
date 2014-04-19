require 'file_store/base_store'
require_dependency "file_helper"

require 'azure'

module FileStore
  class AzureStore < BaseStore

    def store_upload(file, upload, content_type = nil)
      path = get_path_for_upload(file, upload)
      store_file(file, path, upload.original_filename, content_type)
    end

    def store_optimized_image(file, optimized_image)
      path = get_path_for_optimized_image(file, optimized_image)
      store_file(file, path)
    end

    def store_avatar(file, avatar, size)
      path = get_path_for_avatar(file, avatar, size)
      store_file(file, path)
    end

    def remove_upload(upload)
      remove_file(upload.url)
    end

    def remove_optimized_image(optimized_image)
      remove_file(optimized_image.url)
    end

    def has_been_uploaded?(url)
      url.start_with?(absolute_base_url)
    end

    def absolute_base_url
      "//#{azure_storage_account}.blob.core.windows.net/#{azure_container}"
    end

    def external?
      true
    end

    def internal?
      !external?
    end

    def download(upload)
      url = SiteSetting.scheme + ":" + upload.url
      max_file_size = [SiteSetting.max_image_size_kb, SiteSetting.max_attachment_size_kb].max.kilobytes

      FileHelper.download(url, max_file_size, "discourse-azure")
    end
    
    def avatar_template(avatar)
      template = relative_avatar_template(avatar)
      "#{absolute_base_url}/#{template}"
    end

    private

    def get_path_for_upload(file, upload)
      "#{upload.id}#{upload.sha1}#{upload.extension}"
    end

    def get_path_for_optimized_image(file, optimized_image)
      "#{optimized_image.id}#{optimized_image.sha1}_#{optimized_image.width}x#{optimized_image.height}#{optimized_image.extension}"
    end

    def get_path_for_avatar(file, avatar, size)
      relative_avatar_template(avatar).gsub("{size}", size.to_s)
    end

    def relative_avatar_template(avatar)
      "avatars/#{avatar.sha1}/{size}#{avatar.extension}"
    end

    def store_file(file, path, filename = nil, content_type = nil)
      # if this fails, it will throw an exception
      upload(file, path, filename, content_type)
      # url
      "#{absolute_base_url}/#{path}"
    end

    def remove_file(url)
      return unless has_been_uploaded?(url)
      filename = File.basename(url)
      remove(filename)
    end

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
      raise Discourse::SiteSettingMissing.new("azure_blob_container")     if SiteSetting.azure_blob_container.blank?
      raise Discourse::SiteSettingMissing.new("azure_storage_account")     if SiteSetting.azure_storage_account.blank?
      raise Discourse::SiteSettingMissing.new("azure_storage_access_key") if SiteSetting.azure_storage_access_key.blank?

      load_azure_settings()
    end

    def get_or_create_directory(container)
      check_missing_site_settings()

      azure_blob_service = Azure::BlobService.new

      options = { :public_access_level => "blob" }

      begin
        azure_blob_service.create_container(container, options)
      rescue Exception => e
        # NOTE: If the container already exists an exception will be thrown
        # so eat it
        Rails.logger.warn(e.message)
      end

      azure_blob_service
    end

    def upload(file, unique_filename, filename=nil, content_type=nil)
      metadata = { }
      metadata[:content_disposition] = "attachment; filename=\"#{filename}\"" if filename

      options = { :metadata => metadata }

      if content_type
        options[:content_type] = content_type
      else
        options[:content_type] = get_content_type(unique_filename)
      end

      get_or_create_directory(azure_container).create_block_blob(azure_container, unique_filename, file.read(), options)
    end

    def remove(unique_filename)
      check_missing_site_settings()
      azure_blob_service = Azure::BlobService.new
      azure_blob_service.delete_blob(azure_container, unique_filename)
    end
    
    def get_content_type(filename)
      ext = File.extname(filename)
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