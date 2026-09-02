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
        report_error(e, params)
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
          report_error(e, params)
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
          report_error(e, params)
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
          report_error(e, params)
          response = {error: t("s3_multipart.errors.complete"), upload_id: params[:upload_id]}
        ensure
          render :json => response
        end
      end


      # Was `Airbrake.notify`. The airbrake gem was removed from Cubebrush in the
      # 2026-07 move to Better Stack, so this raised
      # `NameError: uninitialized constant S3Multipart::UploadsController::Airbrake`
      # *from inside all four rescues above* — masking the original exception and
      # 500ing the request instead of rendering the {error: ...} JSON the uploader
      # client expects. (Better Stack b631e221, 3 events from 2026-07-16.)
      #
      # Prefer the host application's reporter when it defines one, otherwise fall
      # back to the Rails error reporter, so the gem carries no hard dependency on
      # either. Both are no-ops rather than raisers when reporting is unconfigured.
      #
      # `session` is deliberately no longer sent: it can carry credentials, and
      # modern reporters attach request/user context themselves.
      def report_error(e, params)
        context = {parameters: params.respond_to?(:to_unsafe_h) ? params.to_unsafe_h : params}

        if defined?(::ErrorReporter)
          ::ErrorReporter.notify(e, context)
        elsif defined?(Rails) && Rails.respond_to?(:error)
          Rails.error.report(e, handled: true, context: context)
        end
      end
  end
end
