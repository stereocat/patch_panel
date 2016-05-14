require 'hashie'
require 'patch_panel_exceptions'
require 'patch_panel_manager'
require 'patch_panel_flowbuilder'
require 'topology'
require 'view/text'

# Software patch-panel.
class PatchPanel < Trema::Controller
  timer_event :flood_lldp_frames, interval: 1.sec

  attr_reader :topology

  LLDP_DESTINATION_MAC_ADDRESS = "01:80:c2:00:00:0e"

  def start(_args)
    @ppmgr = PatchPanelManager.new
    logger.info 'PatchPanel started.'
    @topology = Topology.new
    @topology.add_observer View::Text.new(logger)
    logger.info 'Topology started.'
  end

  def add_observer(observer)
    @topology.add_observer observer
  end

  def switch_ready(dpid)
    logger.info "#switch_ready dpid=#{dpid}"
    add_default_drop_entry(dpid)
    add_lldp_packet_in_entry(dpid)
    send_message dpid, Features::Request.new
  end

  def features_reply(dpid, features_reply)
    @topology.add_switch dpid, features_reply.physical_ports.select(&:up?)
  end

  def switch_disconnected(dpid)
    logger.info "#switch_disconnected dpid=#{dpid}"
    @topology.delete_switch dpid
  end

  def port_modify(_dpid, port_status)
    updated_port = port_status.desc
    return if updated_port.local?
    if updated_port.down?
      @topology.delete_port updated_port
    elsif updated_port.up?
      @topology.add_port updated_port
    else
      fail 'Unknown port status.'
    end
  end

  def packet_in(dpid, packet_in)
    if packet_in.lldp?
      @topology.maybe_add_link Link.new(dpid, packet_in)
    else
      @topology.maybe_add_host(packet_in.source_mac,
                               packet_in.source_ip_address,
                               dpid,
                               packet_in.in_port)
    end
  end

  def flood_lldp_frames
    @topology.ports.each do |dpid, ports|
      send_lldp dpid, ports
    end
  end

  # for backward compatibility (used in bin/patch_panel)
  def create_patch(dpid, port_a, port_b)
    create_patch_with(dpid: dpid, inport: port_a, outport: port_b)
    create_patch_with(dpid: dpid, inport: port_b, outport: port_a)
  end

  # for backward compatibility (used in bin/patch_panel)
  def delete_patch(dpid, port_a, port_b)
    delete_patch_with(dpid: dpid, inport: port_a, outport: port_b)
    delete_patch_with(dpid: dpid, inport: port_b, outport: port_a)
  end

  # @param [Hash,Hashie] target patch flow rules
  def create_patch_with(target)
    if @ppmgr.conflict_exists?(target)
      raise PatchLayerConflictError, 'Found layer conflicted patch'
    end
    if @ppmgr.include?(target)
      raise PatchAlreadyExistsError, 'Target patch already exists'
    end
    add_flow_entries target
  end

  # @param [Hash,Hashie] target patch flow rules
  def delete_patch_with(target)
    unless @ppmgr.include?(target)
      raise PatchNotFoundError, 'Target patch not found'
    end
    delete_flow_entries target
  end

  def patch_list
    # change list of PatchData object to list of Hash
    @ppmgr.list.map {|item| item.data }
  end

  private

  def send_lldp(dpid, ports)
    ports.each do |each|
      port_number = each.number
      send_packet_out(
          dpid,
          actions: SendOutPort.new(port_number),
          raw_data: lldp_binary_string(dpid, port_number)
      )
    end
  end

  def lldp_binary_string(dpid, port_number)
    destination_mac = Pio::Mac.new(LLDP_DESTINATION_MAC_ADDRESS)
    if destination_mac
      Pio::Lldp.new(dpid: dpid,
                    port_number: port_number,
                    destination_mac: destination_mac).to_binary
    else
      Pio::Lldp.new(dpid: dpid, port_number: port_number).to_binary
    end
  end

  def add_lldp_packet_in_entry(dpid)
    send_flow_mod_add(dpid, priority: 1,
                      match: Match.new(
                          destination_mac_address: LLDP_DESTINATION_MAC_ADDRESS),
                      actions: SendOutPort.new(:controller))
  end

  # default drop (minimum priority)
  def add_default_drop_entry(dpid)
    send_flow_mod_add(dpid, priority: 0, match: Match.new)
  end

  # @param [Hash,Hashie] target patch data (a flow rule)
  def add_flow_entries(target)
    # Existance of :dpid key is guaranteed by Grape API definition.
    logger.info "#add_flow_entries, dpid=#{target[:dpid]}"
    priority = build_priority(target)
    match = build_match_condition(target)
    actions = build_action_conditions(target)
    send_flow_mod_add(target[:dpid],
                      priority: priority, match: match, actions: actions)
    @ppmgr.append target
  end

  # @param [Hash,Hashie] target patch data (a flow rule)
  def delete_flow_entries(target)
    # Existance of :dpid key is guaranteed by Grape API definition.
    logger.info "#delete_flow_entries, dpid=#{target[:dpid]}"
    match = build_match_condition(target)
    send_flow_mod_delete(target[:dpid], match: match)
    @ppmgr.delete target
  end


end
