ActiveAdmin.register_page 'Utilities' do
  menu priority: 10, label: 'Utilities'

  content title: 'CIViC Utilities' do
    columns do
      column do
        panel "Merge Users" do
          all_users = User.all.sort_by(&:display_name)
          form id: :merge_users_form do |f|
            f.label "User to keep:"
            f.select :user_to_keep, name: :user_to_keep, form: :merge_users_form do
              all_users.each do |user|
                f.option "#{user.display_name} (#{user.email}), #{user.id})", value: user.id
              end
            end
            f.br
            f.br
            f.label "User to remove:"
            f.select :user_to_remove, name: :user_to_remove, form: :merge_users_form do
              all_users.each do |user|
                f.option "#{user.display_name} (#{user.email}), #{user.id})", value: user.id
              end
            end
            f.br
            f.br
            f.button "Merge", formmethod: :post, form: 'merge_users_form', formaction: admin_utilities_merge_users_path, type: 'submit'
          end
        end
        panel "Merge Variants" do
          variants_with_gene_names = Variant.joins(:gene)
          .select('genes.name as gene_name', 'variants.name', 'variants.id')
          .order('gene_name ASC, variants.name ASC')
          .map { |v| [ "#{v.name} - #{v.id} (#{v.gene_name})", v.id] }
          form id: :merge_variants_form do |f|
            f.label "Variant to keep:"
            f.select :variant_to_keep, name: :variant_to_keep, form: :merge_variants_form do
              variants_with_gene_names.each do |(name, val)|
                f.option name, value: val
              end
            end
            f.br
            f.br
            f.label "Variant to remove:"
            f.select :variant_to_remove, name: :variant_to_remove, form: :merge_variants_form do
              variants_with_gene_names.each do |(name, val)|
                f.option name, value: val
              end
            end
            f.br
            f.br
            f.button "Merge", formmethod: :post, form: 'merge_variants_form', formaction: admin_utilities_merge_variants_path, type: 'submit'
          end
        end
        panel "Merge Drugs" do
          all_drugs = Drug.order('name asc').all
          form id: :merge_drugs_form do |f|
            f.label "Drug to keep:"
            f.select :drug_to_keep, name: :drug_to_keep, form: :merge_drugs_form do
              all_drugs.each do |drug|
                f.option "#{drug.name} (#{drug.id})", value: drug.id
              end
            end
            f.br
            f.br
            f.label "Drug to remove:"
            f.select :drug_to_remove, name: :drug_to_remove, form: :merge_drugs_form do
              all_drugs.each do |drug|
                f.option "#{drug.name} (#{drug.id})", value: drug.id
              end
            end
            f.br
            f.br
            f.button "Merge", formmethod: :post, form: 'merge_drugs_form', formaction: admin_utilities_merge_drugs_path, type: 'submit'
          end
        end
      end
      column do
        panel "Add External Source" do
          form id: :pubmed_form do |f|
            f.label "Pubmed ID"
            f.input type: :text, name: :pubmed_id, size: 12
            f.button "Add", formmethod: :post, form: 'pubmed_form', formaction: admin_utilities_add_source_path, type: 'submit'
          end
        end
        panel "Add New Drug" do
          form id: :add_drug_form do |f|
            f.label "Drug Name"
            f.input type: :text, name: :drug_name, size: 25
            f.button "Add", formmethod: :post, form: 'add_drug_form', formaction: admin_utilities_add_drug_path, type: 'submit'
          end
        end
      end
    end
  end


  page_action :add_source, method: :post do
    proposed_pubmed_id = params[:pubmed_id] && params[:pubmed_id].strip
    notice = if proposed_pubmed_id.blank?
               "No PubMed Id provided."
             elsif (source = Source.find_by(pubmed_id: proposed_pubmed_id))
               "Source '#{source.description}' already present."
             elsif (citation = Scrapers::PubMed.get_citation_from_pubmed_id(proposed_pubmed_id)).present?
               Source.create(pubmed_id: proposed_pubmed_id, description: citation)
               "Source '#{citation}' added to CIViC."
             else
               "Source with PubMed Id #{proposed_pubmed_id} not found or PubMed is unreachable."
             end
    redirect_to admin_utilities_path, notice: notice
  end

  page_action :add_drug, method: :post do
    proposed_drug_name = params[:drug_name] && params[:drug_name].strip.downcase
    notice = if proposed_drug_name.present?
                if existing_drug = Drug.where('lower(name) = ?', proposed_drug_name).first
                  "Drug '#{existing_drug.name}' already exists!"
                else
                  drug = Drug.create(name: proposed_drug_name)
                  "Created drug '#{drug.name}'!"
                end
              else
                "New drug cannot have blank name!"
              end
    redirect_to admin_utilities_path, notice: notice
  end

  page_action :merge_variants, method: :post do
    variant_to_remove = Variant.includes(:evidence_items).find(params[:variant_to_remove])
    variant_to_keep = Variant.find(params[:variant_to_keep])
    notice = if variant_to_remove == variant_to_keep
               "Cannot merge a variant with itself."
             else
               variant_to_remove.evidence_items.each do |ei|
                 ei.variant = variant_to_keep
                 ei.save
               end
               variant_to_remove.soft_delete!
               variant_to_remove.save
               variant_to_remove.suggested_changes.each do |sg|
                 sg.delete
                 sg.save
               end
               "Evidence Items from #{variant_to_remove.name} moved to #{variant_to_keep.name}."
             end
    redirect_to admin_utilities_path, notice: notice
  end

  page_action :merge_users, method: :post do
    user_to_remove = User.find(params[:user_to_remove])
    user_to_keep = User.find(params[:user_to_keep])
    notice = if user_to_remove == user_to_keep
               "Cannot merge a user with itself."
             else
               MergeAccounts.new.perform(user_to_keep, user_to_remove)
               "Users merged."
             end
    redirect_to admin_utilities_path, notice: notice
  end

  page_action :merge_drugs, method: :post do
    drug_to_remove = Drug.find(params[:drug_to_remove])
    drug_to_keep = Drug.find(params[:drug_to_keep])

    notice = if drug_to_remove == drug_to_keep
               "Cannot merge a Drug with itself"
             else
               drug_to_remove.evidence_items.each do |ei|
                 current_drugs = ei.drugs
                 current_drugs -= [drug_to_remove]
                 current_drugs += [drug_to_keep]
                 ei.drugs = current_drugs
                 ei.save
               end
               drug_to_remove.destroy
               "Drugs Merged"
             end

    redirect_to admin_utilities_path, notice: notice
  end
end
