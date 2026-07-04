Feed.seed_bbc_feeds!
Feed.seed_nyt_feeds!
puts "Seeded #{Feed.count} feeds."

# Bootstrap the first admin account (see AdminBootstrap for where the values
# come from) so the app is reachable after the users table is created — after
# that, admins manage everyone (including themselves) from /admin/users.
if User.count.zero? && AdminBootstrap.configured?
  User.create!(username: AdminBootstrap.username, email: AdminBootstrap.email, password: AdminBootstrap.password, role: "admin")
  puts "Seeded initial admin user \"#{AdminBootstrap.username}\"."
end
