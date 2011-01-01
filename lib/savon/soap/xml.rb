require "builder"
require "crack/xml"
require "gyoku"

require "savon/soap"
require "savon/core_ext/hash"

module Savon
  module SOAP

    # = Savon::SOAP::XML
    #
    # Represents the SOAP request XML. Contains various global and per request/instance settings
    # like the SOAP version, header, body and namespaces.
    class XML

      # XML Schema Type namespaces.
      SchemaTypes = {
        "xmlns:xsd" => "http://www.w3.org/2001/XMLSchema",
        "xmlns:xsi" => "http://www.w3.org/2001/XMLSchema-instance"
      }

      def self.to_hash(xml)
        (Crack::XML.parse(xml) rescue {}).find_soap_body
      end

      # Accepts an +endpoint+, an +input+ tag and a SOAP +body+.
      def initialize(endpoint = nil, input = nil, body = nil)
        self.endpoint = endpoint if endpoint
        self.input = input if input
        self.body = body if body
      end

      # Accessor for the SOAP +input+ tag.
      attr_accessor :input

      # Accessor for the SOAP +endpoint+.
      attr_accessor :endpoint

      # Sets the SOAP +version+.
      def version=(version)
        raise ArgumentError, "Invalid SOAP version: #{version}" unless SOAP::Versions.include? version
        @version = version
      end

      # Returns the SOAP +version+. Defaults to <tt>Savon.soap_version</tt>.
      def version
        @version ||= Savon.soap_version
      end

      # Sets the SOAP +header+ Hash.
      attr_writer :header

      # Returns the SOAP +header+. Defaults to an empty Hash.
      def header
        @header ||= {}
      end

      # Sets the SOAP envelope namespace.
      attr_writer :env_namespace

      # Returns the SOAP envelope namespace. Defaults to :env.
      def env_namespace
        @env_namespace ||= :env
      end

      # Sets the +namespaces+ Hash.
      attr_writer :namespaces

      # Returns the +namespaces+. Defaults to a Hash containing the SOAP envelope namespace.
      def namespaces
        @namespaces ||= begin
          key = env_namespace.blank? ? "xmlns" : "xmlns:#{env_namespace}"
          { key => SOAP::Namespace[version] }
        end
      end

      # Sets the default namespace identifier.
      attr_writer :namespace_identifier

      # Returns the default namespace identifier.
      def namespace_identifier
        @namespace_identifier ||= :wsdl
      end

      # Accessor for the default namespace URI.
      attr_accessor :namespace

      # Accessor for the <tt>Savon::WSSE</tt> object.
      attr_accessor :wsse

      # Accessor for the SOAP +body+. Expected to be a Hash that can be translated to XML via Gyoku.xml
      # or any other Object responding to to_s.
      attr_accessor :body

      # Accepts a +block+ and yields a <tt>Builder::XmlMarkup</tt> object to let you create custom XML.
      def xml
        @xml = yield builder if block_given?
      end

      # Accepts an XML String and lets you specify a completely custom request body.
      attr_writer :xml

      # Returns the XML for a SOAP request.
      def to_xml
        @xml ||= tag(builder, :Envelope, complete_namespaces) do |xml|
          tag(xml, :Header) { xml << header_for_xml } unless header_for_xml.empty?
          tag(xml, :Body) { xml.tag!(*input) { xml << body_to_xml } }
        end
      end

    private

      # Returns a new <tt>Builder::XmlMarkup</tt> object.
      def builder
        builder = Builder::XmlMarkup.new
        builder.instruct!
        builder
      end

      # Expects a builder +xml+ instance, a tag +name+ and accepts optional +namespaces+
      # and a block to create an XML tag.
      def tag(xml, name, namespaces = {}, &block)
        return xml.tag! name, namespaces, &block if env_namespace.blank?
        xml.tag! env_namespace, name, namespaces, &block
      end

      # Returns the complete Hash of namespaces.
      def complete_namespaces
        defaults = SchemaTypes.dup
        defaults["xmlns:#{namespace_identifier}"] = namespace if namespace
        defaults.merge namespaces
      end

      # Returns the SOAP header as an XML String.
      def header_for_xml
        @header_for_xml ||= Gyoku.xml(header) + wsse_header
      end

      # Returns the WSSE header or an empty String in case WSSE was not set.
      def wsse_header
        wsse.respond_to?(:to_xml) ? wsse.to_xml : ""
      end

      # Returns the SOAP body as an XML String.
      def body_to_xml
        body.kind_of?(Hash) ? Gyoku.xml(body) : body.to_s
      end


      # BEGIN multipart methods
    public
      # Use sort functionality in  Mail::Body.sort!() to order parts
      # An array of mime types is expected 
      # E.g. this makes the xml appear before an attached image: ["text/xml", "image/jpeg"]
      attr_accessor :parts_sort_order
      
      # adds a Part object to the current SOAP "message"
      # Parts are really attachments
      def add_part(part)
        @parts ||= Array.new
        @parts << part
      end
      # check if any parts have been added
      def has_parts?
        @parts ||= Array.new
        !@parts.empty?
      end

      # returns the mime message for a multipart request
      def request_message
        if @parts.empty?
          return nil
        end

        @request_message = Part.new do
          content_type 'multipart/related; type="text/xml"'
        end

        soap_body = self.to_xml
        soap_message = Part.new do
          content_type 'text/xml; charset=utf-8'
          add_content_transfer_encoding
          body soap_body
        end
        @request_message.add_part(soap_message)
        @parts.each do |part|
          @request_message.add_part(part)
        end
        #puts @request_message
        @request_message
      end
      # END multipart methods
      
    end
  end
end
