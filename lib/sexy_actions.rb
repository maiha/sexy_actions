module SexyActions
  class Responder < ActionController::MimeResponds::Responder
    def initialize(owner, action)
      @owner  = owner
      @action = action
      @order  = []
    end

    def respond
      raise NotImplementedError
    end

    def blank?
      @order.blank?
    end

    def custom(mime_type, &block)
      mime_type = mime_type.is_a?(Mime::Type) ? mime_type : Mime::Type.lookup(mime_type.to_s)
      render_method = render_method_for(mime_type)
      block ||= proc{ render :action => action_name }
      @order << mime_type
      @owner.send :define_method, render_method, &block
      @owner.send :private, render_method
    end

    def render_method_for(mime_type)
      mime_type = mime_type.is_a?(Mime::Type) ? mime_type : Mime::Type.lookup(mime_type.to_s)
      raise "mime_type error: expect Mime::Type but got #{mime_type.class}" unless mime_type.is_a?(Mime::Type)
      "render_#{@action}_for_#{mime_type.to_sym.to_s.downcase}"
    end

    def available_mimes_for(controller)
      if controller.class.use_accept_header
        mimes = Array(Mime::Type.lookup_by_extension(controller.request.parameters[:format]) || controller.request.accepts)
      else
        mimes = [controller.request.format]
      end
      mimes.map!{|mime_type|
        mime_type = Mime::Type.lookup(mime_type.to_s) unless mime_type.is_a?(Mime::Type)
        mime_type = @order.first if mime_type == Mime::ALL
        mime_type
      }.compact!
      mimes << Mime::ALL if @order.include?(Mime::ALL)
      return mimes
    end

    def mime_for(controller)
      available_mimes_for(controller).each do |mime|
        return mime if controller.respond_to?(render_method_for(mime), true)
      end
      return nil
    end
  end

  def self.included(base)
    base.class_eval do
      extend  ClassMethods
      include InstanceMethods
      alias_method_chain :default_render, :sexy_mime_responds
    end
  end

  module ClassMethods
    def method_missing(action, *arguments, &block)
      if action_methods.include?(action.to_s)
        mime_responder_for(action)
      elsif block
        define_method action, &block
      else
        super
      end
    ensure
      @action_methods = nil     # clear cache
    end

    def mime_responder_for(action)
      (@mime_responders||={})[action.to_s] ||= Responder.new(self, action.to_s)
    end
  end

  module InstanceMethods
  private
    def mime_responder
      self.class.mime_responder_for(action_name)
    end

    def default_render_with_sexy_mime_responds
      if mime_responder.blank?
        return default_render_without_sexy_mime_responds
      end

      mime_type = mime_responder.mime_for(self)
      if mime_type
        render_method = mime_responder.render_method_for(mime_type)
        response.template.template_format = mime_type.to_sym
        response.content_type = mime_type.to_s
        return send(render_method)
      end

      head :not_acceptable
    end
  end
end
