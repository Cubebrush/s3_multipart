module S3Multipart
  class UploadsController < ApplicationController

    def create
      begin
        upload = Upload.create(permitted_params)
        upload.execute_callback(:begin, session)
        response = upload.to_json
      rescue FileTypeError, FileSizeError => e
        response = {error: e.message}
      rescue => e
        logger.error "EXC: #{e.message}"
        airbrake(e, params)
        response = { error: t("s3_multipart.errors.create") }
      ensure
        render :json => response
      end
    end

    def update
      return complete_upload if params[:parts]
      return sign_batch if params[:content_lengths]
      return sign_part if params[:content_length]
    end

    private

      def permitted_params
        params.permit!
      end

      def sign_batch
        begin
          response = Upload.sign_batch(params)
        rescue => e
          logger.error "EXC: #{e.message}"
          airbrake(e, params)
          response = {error: t("s3_multipart.errors.update")}
        ensure
          render :json => response
        end
      end

      def sign_part
        begin
          response = Upload.sign_part(params)
        rescue => e
          logger.error "EXC: #{e.message}"
          airbrake(e, params)
          response = {error: t("s3_multipart.errors.update")}
        ensure
          render :json => response
        end
      end

      def complete_upload
        begin
          response = Upload.complete(params)
          upload = Upload.find_by_upload_id(params[:upload_id])
          if response.present?
            upload.update(location: response[:location])
          end  
          complete_response = upload.execute_callback(:complete, session)
          response ||= {}
          response[:extra_data] = complete_response if complete_response.is_a?(Hash)
          complete_response
        rescue => e
          logger.error "EXC: #{e.message}"
          airbrake(e, params)
          response = {error: t("s3_multipart.errors.complete"), upload_id: params[:upload_id]}
        ensure
          render :json => response
        end
      end


      def airbrake(e, params)
        Airbrake.notify(
          e,
          :parameters    => params,
          :session      => session
        )
      end
  end
end
