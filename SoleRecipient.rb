require_relative "Nx.jar"
java_import "com.nuix.nx.NuixConnection"
java_import "com.nuix.nx.LookAndFeelHelper"
java_import "com.nuix.nx.dialogs.ChoiceDialog"
java_import "com.nuix.nx.dialogs.CustomDialog"
java_import "com.nuix.nx.dialogs.CommonDialogs"
java_import "com.nuix.nx.dialogs.ProgressDialog"

LookAndFeelHelper.setWindowsIfMetal
NuixConnection.setUtilities($utilities)
NuixConnection.setCurrentNuixVersion(NUIX_VERSION)

input_dialog = CustomDialog.new
input_dialog.setTitle("Sole Recipient")
input_dialog.appendTextField("scope_query","Scope Query","")
input_dialog.appendTextField("address","Email Address","")
input_dialog.appendCheckBox("include_families","Include Families",false)
input_dialog.appendTextField("tag_template","Tag Template","Sole Recipient|{address}")
input_dialog.appendOkayCancelButtons

input_dialog.validateBeforeClosing do |values|
	if values["address"].strip.empty?
		CommonDialogs.showError("Email Address cannot be empty.")
		next false
	end
	next true
end

input_dialog.display
if input_dialog.getDialogResult == true
	values = input_dialog.toMap
	recipient_fields = [
		"to",
		"cc",
		"bcc",
	]
	ProgressDialog.forBlock do |pd|
		pd.setTitle("Sole Recipient")
		pd.setSubProgressVisible(false)

		if !values["scope_query"].strip.empty?
			pd.logMessage("Scope Query: #{values["scope_query"]}")
		end
		pd.logMessage("Include Families: #{values["include_families"]}")
		pd.logMessage("Address: #{values["address"]}")

		query = recipient_fields.map{|field| "#{field}:\"#{values["address"]}\""}.join(" OR ")
		query = "(#{query})"
		query += " AND has-communication:1"
		if !values["scope_query"].strip.empty?
			query += " AND (#{values["scope_query"]})"
		end
		pd.logMessage("Query: #{query}")
		pd.setMainStatus("Searching")
		hits = $current_case.search(query)
		pd.logMessage("Recipient Hits: #{hits.size}")
		pd.logMessage("Filtering to single recipient entries...")
		sole_hits = Hash.new{|h,k|h[k]=[]}
		pd.setMainProgress(0,hits.size)
		pd.setMainStatus("Locating Sole Recipient Items")
		hits.each_with_index do |item,index|
			break if pd.abortWasRequested
			pd.setMainProgress(index+1)
			pd.setSubStatus("#{index+1}/#{hits.size}")
			communication = item.getCommunication
			if communication.nil?
				pd.logMessage("#{item.getGuid} has no communication associated")
			else
				addresses = []
				addresses += communication.getTo.to_a
				addresses += communication.getCc.to_a
				addresses += communication.getBcc.to_a
				distinct_addresses = addresses.map{|a|a.getAddress.downcase}.uniq
				if distinct_addresses.size == 1
					sole_hits[distinct_addresses.first] << item
				end
			end
		end

		iutil = $utilities.getItemUtility
		annotater = $utilities.getBulkAnnotater
		pd.setMainStatus("Applying Tags")
		pd.setMainProgress(0,sole_hits.size)
		sole_hit_index = 0
		sole_hits.each do |address,items|
			break if pd.abortWasRequested
			sole_hit_index += 1
			pd.setMainProgress(sole_hit_index)
			pd.setSubStatus("#{sole_hit_index}/#{sole_hits.size}")
			target_items = items
			if values["include_families"]
				target_items = iutil.findFamilies(items)
			end
			tag = values["tag_template"].gsub(/\{address\}/,address.downcase)
			pd.logMessage("Tagging #{items.size} with: #{tag}")
			annotater.addTag(tag,target_items)
		end

		if pd.abortWasRequested
			pd.setMainStatusAndLogIt("User Aborted")
		else
			pd.setMainStatusAndLogIt("Completed")
		end
	end
end