class TreeBuilderImages < TreeBuilder
  has_kids_for ExtManagementSystem, [:x_get_tree_ems_kids]

  include TreeBuilderArchived

  def tree_init_options(_tree_name)
    {
      :leaf => "ManageIQ::Providers::CloudManager::Template"
    }
  end

  def set_locals_for_render
    locals = super
    locals.merge!(
      :tree_id   => "images_treebox",
      :tree_name => "images_tree",
      :id_prefix => "images_",
      :autoload  => true
    )
  end

  def root_options
    [_("Images by Provider"), _("All Images by Provider that I can see")]
  end

  def x_get_tree_roots(count_only, _options)
    objects = Rbac.filtered(EmsCloud.order("lower(name)"), :match_via_descendants => TemplateCloud) +
              x_get_tree_arch_orph_nodes("Images")
    count_only_or_objects(count_only, objects)
  end

  def x_get_tree_ems_kids(object, count_only)
    objects = Rbac.filtered(object.miq_templates.order("name"))
    count_only ? objects.length : objects
  end
end
