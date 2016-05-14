require 'grape'
require 'trema'
require 'patch_panel_exceptions'

# Remote PatchPanel class proxy
class PatchPanel
  def self.method_missing(method, *args, &block)
    socket_dir = if FileTest.exists?('PatchPanel.ctl')
                   '.'
                 else
                   ENV['TREMA_SOCKET_DIR'] || Trema::DEFAULT_SOCKET_DIR
                 end
    # puts "socket_dir = #{socket_dir}" # debug
    pp_controller = Trema.trema_process('PatchPanel', socket_dir).controller
    # puts "controller=#{pp_controller.class.to_s}, method=#{method.to_s}" # debug
    pp_controller.__send__(method, *args, &block)
  end
end

# REST API of PatchPanel
class RestApi < Grape::API
  format :json

  PRIORITY_RANGE = 0..0xffff
  MAC_ADDR_REGEXP = /^(?:[[:xdigit:]]{2}([-:]))(?:[[:xdigit:]]{2}\1){4}[[:xdigit:]]{2}$/
  VLAN_VID_RANGE = 1..4095

  before do
    header 'Access-Control-Allow-Origin', '*'
  end

  helpers do
    def rest_api
      yield
    rescue PatchPanel::PatchNotFoundError => patch_not_found_error
      error! patch_not_found_error.message, 404
    rescue PatchPanel::PatchAlreadyExistsError => patch_already_exists_error
      error! patch_already_exists_error.message, 409
# debug
#    rescue StandardError => standard_error
#      error! standard_error.message, 400
    end
  end

  desc 'DocumentRoot'
  get '/' do
    content_type 'text/html'
    file 'public/index.html'
  end

  desc 'CSS'
  get '/css/base.css' do
    content_type 'text/css'
    file 'public/css/base.css'
  end

  desc 'javaScript'
  get '/js/topology_graph.js' do
    content_type 'text/javascript'
    file 'public/js/topology_graph.js'
  end

  desc 'Get all switches as list'
  get '/patch/switches' do
    rest_api { PatchPanel.topology.switches.map(&:to_hex) }
  end

  desc 'Get all ports of a switch as list'
  get '/patch/switch/:dpid/ports' do
    # TODO: ports of a switch
  end

  desc 'Get all links as list'
  get '/patch/physical_links' do
    rest_api { PatchPanel.physical_links }
  end

  desc 'Get all patch-connect rules in switch internal'
  get '/patch/logical_wires' do
    rest_api { PatchPanel.logical_wires }
  end

  desc 'Get whole physical/logical connections'
  get 'patch/whole_topology' do
    rest_api { PatchPanel.whole_topology }
  end

  desc 'Get all patch as list'
  get '/patch/flow' do
    rest_api { PatchPanel.patch_list }
  end

  desc 'Create a patch'
  params do
    optional :priority, type: Integer, values: PRIORITY_RANGE,
             desc: 'Priority of the flow rule.'
    requires :dpid, type: Integer, desc: 'Datapath ID.'
    requires :inport, type: Integer, desc: 'Inbound port number. (Match)'
    optional :outport, type: Integer, desc: 'Outbound port number. (Action)'
    optional :outports, type: Array[Integer],
             desc: 'Array of outbound port number. (Action)'
    exactly_one_of :outport, :outports
    # if :eth_src and/or :eth_dst exists, the flow rule is for layer2-patch
    optional :eth_src, type: String, regexp: MAC_ADDR_REGEXP,
             desc: 'Inbound source MAC address. (Match)'
    optional :eth_dst, type: String, regexp: MAC_ADDR_REGEXP,
             desc: 'Inbound destination MAC address. (Match)'
    optional :vlan_vid, type: Integer, values: VLAN_VID_RANGE,
             desc: 'Inbound VLAN ID. (Match)'
    optional :set_vlan, type: Integer, values: VLAN_VID_RANGE,
             desc: 'Outbound VLAN ID. (Action)'
    # used like that: if match :vlan_vid then :pop_vlan
    optional :pop_vlan, type: Boolean, desc: 'Outbound VLAN ID none. (Action)'
  end
  put '/patch/flow' do
    puts "PUT #{params.to_s}" # debug
    # `params' is instance of Hashie
    rest_api { PatchPanel.create_patch_with(params) }
  end

  desc 'Delete a patch'
  params do
    requires :dpid, type: Integer, desc: 'Datapath ID.'
    requires :inport, type: Integer, desc: 'Inbound port number. (Match)'
    optional :eth_src, type: String, regexp: MAC_ADDR_REGEXP,
             desc: 'Inbound source MAC address. (Match)'
    optional :eth_dst, type: String, regexp: MAC_ADDR_REGEXP,
             desc: 'Inbound destination MAC address. (Match)'
    optional :vlan_vid, type: Integer, values: VLAN_VID_RANGE,
             desc: 'Inbound VLAN ID. (Match)'
  end
  delete '/patch/flow' do
    puts "DELETE #{params.to_s}" # debug
    rest_api { PatchPanel.delete_patch_with(params) }
  end
end
