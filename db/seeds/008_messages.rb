# Create realistic conversation threads between users
puts "Creating message threads and conversations..."

# Get admin users and regular users
admin_users = Spree::User.admin.limit(3).to_a
regular_users = Spree::User.where.not(id: admin_users.map(&:id)).limit(10).to_a

if admin_users.empty?
  puts "Warning: No admin users found. Creating conversations between regular users only."
  admin_users = regular_users.sample(2)
end

# Create 10 conversation threads
10.times do |i|
  # Pick a customer and support agent
  customer = regular_users.sample
  support_agent = admin_users.sample
  
  # Skip if we don't have valid users
  next unless customer && support_agent
  
  # Create a thread for this conversation
  thread = ThreadTable.create!(
    stale: [true, false].sample,
    archived: i > 7 ? true : false, # Archive older threads
    created_at: rand(30.days.ago..Time.now),
    updated_at: [created_at, Time.now].max
  )
  
  # Create a conversation with 3-8 messages
  message_count = rand(3..8)
  conversation_topics = [
    { question: "I haven't received my order yet. Can you help?", answer: "I'd be happy to help! Can you provide your order number?" },
    { question: "How do I return an item?", answer: "You can initiate a return from your account dashboard. Would you like me to guide you through the process?" },
    { question: "Do you offer international shipping?", answer: "Yes! We ship to most countries. Where would you like it shipped?" },
    { question: "My payment didn't go through. What should I do?", answer: "Let me check that for you. Can you tell me which payment method you tried?" },
    { question: "Can I change my shipping address?", answer: "Absolutely! If your order hasn't shipped yet, I can update that for you." },
    { question: "Is this product available in other colors?", answer: "Let me check our inventory for you. Which product are you interested in?" },
    { question: "I received the wrong item.", answer: "I apologize for the inconvenience! I'll help you get this sorted out right away." },
    { question: "How long does shipping usually take?", answer: "Standard shipping typically takes 5-7 business days. Would you like to upgrade to express shipping?" }
  ]
  
  topic = conversation_topics.sample
  base_time = thread.created_at
  
  message_count.times do |msg_idx|
    # Alternate between customer and support agent
    is_customer_message = msg_idx.even?
    
    if is_customer_message
      # Customer message
      message_text = if msg_idx == 0
        topic[:question]
      else
        [
          "Thank you for your help!",
          "Yes, that would be great.",
          "My order number is ##{rand(10000..99999)}",
          "I appreciate your quick response.",
          Faker::Lorem.sentence,
          "Okay, I understand now.",
          "Perfect, thank you so much!"
        ].sample
      end
      
      Message.create!(
        sender_type: 'Spree::User',
        sender_id: customer.id,
        receiver_type: 'Spree::User',
        receiver_id: support_agent.id,
        thread_table_id: thread.id,
        message: message_text,
        is_received: true,
        is_read: msg_idx < message_count - 1, # Last message might be unread
        sentiment: rand(0..1),
        created_at: base_time + (msg_idx * rand(5..30)).minutes,
        updated_at: base_time + (msg_idx * rand(5..30)).minutes
      )
    else
      # Support agent message
      message_text = if msg_idx == 1
        topic[:answer]
      else
        [
          "You're welcome! Is there anything else I can help you with?",
          "I've updated that for you. You should see the changes shortly.",
          "Let me look into that and get back to you in a few minutes.",
          "That's all set! Anything else I can assist with today?",
          Faker::Lorem.sentence,
          "I've sent you an email with the details.",
          "Great! Feel free to reach out if you need anything else."
        ].sample
      end
      
      Message.create!(
        sender_type: 'Spree::User',
        sender_id: support_agent.id,
        receiver_type: 'Spree::User',
        receiver_id: customer.id,
        thread_table_id: thread.id,
        message: message_text,
        is_received: false,
        is_read: true,
        sentiment: rand(0..1),
        created_at: base_time + (msg_idx * rand(5..30)).minutes,
        updated_at: base_time + (msg_idx * rand(5..30)).minutes
      )
    end
  end
  
  puts "Created conversation thread #{i + 1} with #{message_count} messages between #{customer.email} and #{support_agent.email}"
end

# Create a few standalone messages (not part of a thread yet - will be assigned via after_create callback)
puts "Creating standalone messages..."
5.times do
  customer = regular_users.sample
  support = admin_users.sample
  
  next unless customer && support
  
  Message.create!(
    sender_type: 'Spree::User',
    sender_id: customer.id,
    receiver_type: 'Spree::User',
    receiver_id: support.id,
    message: [
      "Hello, I have a question about my recent order.",
      "Can someone help me with tracking information?",
      "I'd like to inquire about wholesale pricing.",
      "Is there a way to subscribe to your newsletter?",
      "Do you have a customer loyalty program?"
    ].sample,
    is_received: true,
    is_read: false,
    sentiment: 0,
    created_at: rand(1.day.ago..Time.now),
    updated_at: rand(1.day.ago..Time.now)
  )
end

puts "Messaging seed data created successfully!"
puts "- #{ThreadTable.count} conversation threads"
puts "- #{Message.count} messages"