require 'hashie'
require 'patch_panel_exceptions'
require 'patch_panel_manager'
require 'patch_panel_flowbuilder'

# Software patch-panel.
class PatchPanel < Trema::Controller
  def start(_args)
    @ppmgr = PatchPanelManager.new
    logger.info 'PatchPanel started.'
  end

  def switch_ready(dpid)
    logger.info "#switch_ready dpid=#{dpid}"
    add_default_drop_entry(dpid)
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

  def add_default_drop_entry(dpid)
    # default drop (minimum priority)
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
