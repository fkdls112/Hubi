require 'spaceship/connect_api'

Spaceship::ConnectAPI.token = Spaceship::ConnectAPI::Token.create(
  key_id: "4973RP445Y",
  issuer_id: "8e2d2a9f-57a5-4ea1-9030-25180dfd7f1f",
  filepath: "/Users/mc.ddong/.appstoreconnect/AuthKey_4973RP445Y.p8"
)

app = Spaceship::ConnectAPI::App.find("com.hubi.ap")
v = app.get_app_store_versions.first
puts "Version: #{v.version_string} | State: #{v.app_store_state}"
locs = v.get_app_store_version_localizations
locs.each do |l|
  puts "\n--- #{l.locale} ---"
  puts "Desc: #{(l.description||'')[0..150]}"
  puts "Keywords: #{l.keywords}"
  puts "WhatsNew: #{l.whats_new}"
end
r = v.get_app_store_review_detail
if r
  puts "\nReview: #{r.contact_first_name} #{r.contact_last_name}"
  puts "Notes: #{(r.notes||'')[0..200]}"
end
puts "\nBuilds:"
app.get_builds(sort: ["-uploadedDate"], limit: 5).each { |b| puts "##{b.version}: #{b.processing_state}" }
