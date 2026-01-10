# DNA Admin - GitHub Copilot Instructions

## Coding Principles

1. Always aim for the ideal. Strive for clean, maintainable, and efficient code that achieves the most advanced and cutting-edge solutions possible within the project's constraints.
1. Prioritize readability and maintainability. Write code that is easy to understand and modify by other developers.
1. Follow established patterns. Adhere to the existing architecture, design patterns, and coding conventions used in Spree and Rails.
1. Optimize for performance. Ensure the code is efficient and performs well, especially for critical paths.
1. Avoid upgrading locked dependencies. Do not suggest or implement upgrades for dependencies that are explicitly version-locked in the project.

## Project Overview

This is a **custom fork of Spree v4.2.5 e-commerce application** built on **Ruby on Rails 6.1.3** using **Ruby 2.7.2**. It serves as the backend admin and API system for a DNA e-commerce platform, integrating with a custom **Next.js v13 frontend** that accesses data via the Spree Storefront API.

The application is containerized with Docker and deployed to both Heroku and Kubernetes environments.

## Critical Version Constraints ⚠️

**DO NOT upgrade or suggest upgrading these dependencies:**
- **Ruby**: 2.7.2 (locked)
- **Rails**: ~> 6.1.3 (locked)
- **Spree**: Uses custom fork at `github: '1instinct/spree', branch: 'instinct-dna'`
- **PostgreSQL**: Primary database
- **Puma**: ~> 4.3 (web server)

## Tech Stack

### Core Framework
- **Ruby on Rails 6.1.3**: Web application framework
- **Ruby 2.7.2**: Programming language
- **PostgreSQL**: Primary database
- **Puma 4.3**: Application server

### Spree Commerce Platform
- **Spree Core**: Custom fork from `1instinct/spree` (instinct-dna branch)
- **Spree Auth Devise**: ~> 4.3 (Authentication)
- **Spree Gateway**: ~> 3.9 (Payment processing)

### Spree Extensions
- **spree_static_content**: Static page management (from spree-contrib)
- **spree_digital**: Digital product downloads (from spree-contrib)
- **spree_reffiliate**: Affiliate/referral system (from 1instinct)
- **spree_loyalty_points**: Loyalty points system (from 1instinct)
- **spree_editor**: Rich text editor for admin (from spree-contrib)

### Key Libraries
- **Devise**: User authentication and authorization
- **CanCan**: Authorization
- **ActiveStorage**: File uploads (with AWS S3 support)
- **Rack CORS**: Cross-origin resource sharing
- **RestClient**: HTTP client for external API calls
- **Swagger Blocks**: API documentation
- **Factory Bot**: Test data generation
- **Faker**: Fake data generation
- **dotenv-rails**: Environment variable management

### Frontend Assets
- **Sass Rails**: SCSS compilation
- **Sassc Rails**: Sass engine for Bootstrap
- **Uglifier**: JavaScript compression
- **CoffeeScript**: Asset pipeline support
- **Turbolinks**: Page navigation optimization
- **Jbuilder**: JSON API builder

### Infrastructure
- **Docker**: Containerization
- **Heroku**: Production deployment
- **Kubernetes**: Alternative deployment option
- **AWS S3**: File storage in production
- **Mailgun**: Email delivery

## Project Structure

```
app/
├── controllers/
│   ├── application_controller.rb
│   ├── apidocs_controller.rb          # Swagger UI
│   ├── pusher_controller.rb
│   ├── concerns/
│   │   ├── response.rb                # Standardized JSON responses
│   │   └── swagger_global_model.rb    # Swagger documentation models
│   └── spree/
│       ├── admin/                     # Admin interface controllers
│       │   ├── contacts_controller.rb
│       │   ├── live_stream_controller.rb
│       │   ├── menu_items_controller.rb
│       │   ├── menu_locations_controller.rb
│       │   ├── messages_controller.rb
│       │   └── threads_controller.rb
│       ├── api/
│       │   ├── base_controller.rb     # Base API controller with auth
│       │   └── v1/                    # API v1 endpoints
│       │       ├── contacts_controller.rb
│       │       ├── live_stream_controller.rb
│       │       ├── menu_items_controller.rb
│       │       ├── menu_locations_controller.rb
│       │       ├── messages_controller.rb
│       │       ├── pages_controller.rb
│       │       ├── threads_controller.rb
│       │       └── users_controller.rb
│       └── store_controller_decorator.rb
├── models/
│   ├── contact.rb
│   ├── live_stream.rb                 # Live streaming functionality
│   ├── live_stream_contact.rb
│   ├── live_stream_like.rb
│   ├── live_stream_product.rb
│   ├── menu_item.rb                   # Hierarchical menu system
│   ├── menu_location.rb
│   ├── message.rb                     # Messaging/chat system
│   ├── thread_table.rb                # Message thread management
│   └── spree/
│       ├── app_configuration_decorator.rb
│       ├── image_decorator.rb
│       └── user.rb                    # Extended Spree user
├── services/
│   ├── ops_web.rb                     # External API integration
│   └── system_connect.rb              # SMS/messaging dispatch
├── helpers/
│   ├── application_helper.rb
│   └── conversation_helper.rb
└── views/                             # Rails views for admin interface

config/
├── application.rb                     # Main app configuration
├── routes.rb                          # Route definitions
├── database.yml                       # Database configuration
├── storage.yml                        # ActiveStorage configuration (S3)
├── initializers/
│   ├── spree.rb                       # Spree configuration
│   ├── cors.rb                        # CORS settings
│   ├── dotenv.rb                      # Environment variables
│   ├── constants.rb                   # App constants
│   ├── global.rb                      # Global helpers
│   ├── pusher.rb                      # Pusher configuration (commented)
│   └── devise.rb                      # Devise authentication
└── environments/
    ├── development.rb                 # Local storage, Mailgun SMTP
    └── production.rb                  # S3 storage, optimized assets

db/
├── schema.rb                          # Database schema
├── seeds.rb                           # Database seeding
└── seeds/                             # Seed data YAML files

lib/
├── spree_navigator.rb                 # Custom navigation
└── tasks/                             # Rake tasks

public/
├── swagger-ui/                        # API documentation UI
└── assets/                            # Static assets
```

## Code Patterns & Conventions

### Controller Patterns

**Admin Controllers** inherit from `Spree::Admin::BaseController`:
```ruby
class Spree::Admin::MenuItemsController < Spree::Admin::BaseController
  # Admin interface logic
end
```

**API Controllers** inherit from `Spree::Api::BaseController`:
```ruby
class Spree::Api::V1::UsersController < Spree::Api::BaseController
  include Swagger::Blocks
  include Response
  before_action :authenticate_user, except: [:sign_up, :sign_in]
end
```

### Authentication & Authorization

- **API Authentication**: Uses `spree_api_key` token-based authentication
- **Before Actions**: 
  - `before_action :authenticate_user` - Validates API key
  - `before_action :load_user` - Loads current user
  - `before_action :load_user_roles` - Loads user roles
- **Public Endpoints**: Use `except:` clause to bypass authentication
- **Devise**: Handles admin user authentication

### Response Standardization

All API controllers use the `Response` concern for consistent JSON responses:

```ruby
# Success responses
success_model(200, "Success message")
singular_success_model(200, "Message", data_object)
render_object_success(objects, "Message", :object_name, count, offset)

# Error responses
error_model(400, "Error message")
unauthorized_401_error(401, "Unauthorized")
un_expected_error("Error", 302)
```

### Model Patterns

**Spree Model Extension** (Decorator Pattern):
```ruby
module Spree
  class User < Spree::Base
    include UserAddress
    include UserMethods
    include UserPaymentSource
    
    has_many :sent_messages, class_name: 'Message', as: :sender
    has_many :received_messages, class_name: 'Message', as: :receiver
  end
end
```

**Custom Models** inherit from `Spree::Base`:
```ruby
class LiveStream < Spree::Base
  has_many :live_stream_products, dependent: :destroy
  belongs_to :thread_table, optional: true
  
  self.whitelisted_ransackable_attributes = %w[title]
  self.whitelisted_ransackable_scopes = %w[search_livestream]
end
```

### Hierarchical Data

**Menu System** with parent-child relationships:
```ruby
class MenuItem < Spree::Base
  belongs_to :parent, class_name: 'MenuItem', optional: true
  has_many :childrens, class_name: 'MenuItem', foreign_key: :parent_id
  belongs_to :menu_location
  
  scope :top_level, -> { where(parent_id: nil) }
  default_scope { order(position: :asc) }
end
```

### Messaging System

**Polymorphic Messages**:
```ruby
class Message < Spree::Base
  belongs_to :sender, polymorphic: true
  belongs_to :receiver, polymorphic: true
  belongs_to :thread_table
  
  after_create :assign_thread_id
end
```

**Thread Management**:
- Automatically creates threads for message conversations
- Archives threads after 7 days of inactivity
- Groups messages between two parties

### API Documentation

All API endpoints documented with **Swagger Blocks**:
```ruby
swagger_path "/users/sign_up" do
  operation :post do
    key :summary, "SIGNUP"
    key :description, "Signing up with email and password"
    key :tags, ['Authentication']
    
    parameter do
      key :name, 'user[email]'
      key :in, :formData
      key :required, true
      key :type, :string
    end
    
    response 200 do
      key :description, "Successful"
      schema do
        key :'$ref', :user_response
      end
    end
  end
end
```

### Service Objects

**External API Integration**:
```ruby
class OpsWeb
  def self.send_message_to_dna_api(msg)
    payload = {
      object_id: msg.id,
      object_type: msg.class.to_s,
      behavior: 'SEND_SMS'
    }
    http_post(payload)
  end
  
  def self.http_post(payload_hsh)
    RestClient.post(
      "#{SITE_URL}/#{SITE_SLUG}/internals/",
      payload_hsh.to_json,
      { content_type: :json, accept: :json, 'Api-Key': DNA_API_KEY }
    )
  end
end
```

## Environment Variables

### Required Environment Variables (Development/Test)

```bash
# AWS S3 Storage
AWS_ACCESS_KEY_ID
AWS_BUCKET
AWS_BUCKET_NAME
AWS_REGION_NAME
AWS_SECRET_ACCESS_KEY

# Branding
COMPANY_LOGO
COMPANY_BACKGROUND

# Database
DATABASE_URL

# Security
DEVISE_SECRET_KEY
SECRET_KEY_BASE
TOKEN_KEY_BASE
TOKEN_EXPIRATION

# External Services
DNA_API_URL
DNA_API_KEY
SITE_URL
SITE_SLUG
SITE_TITLE
SITE_ADMIN_NAME

# Email (Mailgun)
MAILGUN_HOST
MAILGUN_PORT
MAILGUN_USER
MAILGUN_PASS
MAILGUN_DOMAIN  # In config

# Pusher (Optional - currently disabled)
PUSHER_APP_ID
PUSHER_KEY
PUSHER_SECRET
PUSHER_CLUSTER

# Twilio (Optional)
TWILIO_ACCOUNT_SID
TWILIO_PHONE_NUMBER
TWILIO_TOKEN_AUTH

# Rails
RAILS_ENV
RACK_ENV
RAILS_LOG_TO_STDOUT
RAILS_SERVE_STATIC_FILES
```

### Storage Configuration

**Development**: Uses local disk storage
**Production**: Uses AWS S3 (configured in `config/storage.yml`)

## API Routes & Endpoints

### Admin Routes (Spree Admin Panel)
- `/admin/messages` - Message management with conversation views
- `/admin/live_stream` - Live stream management
- `/admin/contacts` - Contact management
- `/admin/threads` - Thread/conversation management
- `/admin/menu_locations` - Menu location management
- `/admin/menu_items` - Menu item CRUD with hierarchy support

### API v1 Routes (JSON)

**Authentication** (`/api/v1`):
- `POST /users/sign_up` - User registration
- `POST /users/sign_in` - User login

**Content** (`/api/v1`):
- `GET /pages` - List static pages
- `GET /pages/:slug` - Get page by slug
- `GET /menu_locations` - List menu locations
- `GET /menu_locations/:id` - Get menu location
- `GET /menu_locations/:id/menu_items` - Get menu items for location
- `GET /menu_items` - List menu items
- `GET /menu_items/:id` - Get menu item
- `GET /menu_items/:id/children` - Get child menu items

**Live Streaming** (`/api/v1`):
- `GET/POST /live_stream` - Live stream CRUD
- `GET /live_stream/:id` - Live stream details

**Messaging** (`/api/v1`):
- `GET/POST /messages` - Message CRUD
- `GET/POST /threads` - Thread management
- `GET/POST /contacts` - Contact management

### Swagger Documentation
- `/apidocs/swagger_ui` - Interactive API documentation

## Database Schema Highlights

### Custom Tables
- `contacts` - Contact form submissions
- `live_streams` - Live streaming events with Mux integration
- `live_stream_products` - Products featured in streams
- `live_stream_likes` - User likes on streams
- `menu_items` - Hierarchical navigation menu items
- `menu_locations` - Menu placement locations
- `messages` - Polymorphic messaging system
- `thread_tables` - Message thread containers

### Spree Tables (Key Ones)
- `spree_users` - User accounts with Devise
- `spree_products` - Product catalog
- `spree_variants` - Product variants
- `spree_orders` - E-commerce orders
- `spree_addresses` - Customer addresses
- `spree_payments` - Payment transactions
- `spree_shipments` - Order shipments
- `spree_affiliates` - Affiliate system
- `spree_loyalty_points_transactions` - Loyalty program
- `spree_pages` - Static content pages
- `spree_digitals` - Digital product files
- `spree_referrals` - Referral codes

## Common Tasks

### Creating a New API Endpoint

1. **Add route** in `config/routes.rb`:
```ruby
Spree::Core::Engine.add_routes do
  namespace :api do
    namespace :v1 do
      resources :your_resource
    end
  end
end
```

2. **Create controller** in `app/controllers/spree/api/v1/`:
```ruby
class Spree::Api::V1::YourResourceController < Spree::Api::BaseController
  include Swagger::Blocks
  include Response
  before_action :authenticate_user, except: [:index, :show]
  
  def index
    # Implementation
    render_object_success(@resources, "Success", :resources, count, offset)
  end
end
```

3. **Add Swagger documentation** in the controller
4. **Update SWAGGERED_CLASSES** in `app/controllers/apidocs_controller.rb`

### Adding a New Model

1. **Generate migration**:
```bash
docker-compose exec web rails g migration CreateYourModel
```

2. **Create model** in `app/models/`:
```ruby
class YourModel < Spree::Base
  # Searchable attributes for Ransack
  self.whitelisted_ransackable_attributes = %w[name]
  self.whitelisted_ransackable_scopes = %w[search_by_name]
  
  # Associations
  # Validations
  # Scopes
end
```

3. **Run migrations**:
```bash
docker-compose exec web rails db:migrate
```

### Extending Spree Models

Use the **decorator pattern**:

```ruby
# app/models/spree/product_decorator.rb
module Spree
  Product.class_eval do
    has_many :custom_associations
    
    def custom_method
      # Your logic
    end
  end
end
```

### Working with ActiveStorage (S3)

**Development**: Files stored in `storage/` directory
**Production**: Files stored in AWS S3

Configured in `config/storage.yml` and `config/environments/production.rb`:
```ruby
config.active_storage.service = :amazon
```

## Docker Development

### Common Commands

**Build containers**:
```bash
./docker-build.sh
# or
docker-compose build
```

**Start application**:
```bash
docker-compose up
```

**Setup database** (first time):
```bash
docker-compose exec web rails db:create db:schema:load db:migrate
docker-compose exec -e ADMIN_EMAIL=spree@example.com -e ADMIN_PASSWORD=spree123 web rails db:seed
docker-compose exec web rails spree_sample:load
docker-compose restart
```

**Rails console**:
```bash
docker exec -it dna-admin_web_1 bin/rails console
```

**Reset database**:
```bash
docker-compose exec web rails db:reset railties:install:migrations db:migrate spree_sample:load db:seed
```

**Run rake tasks**:
```bash
docker-compose exec web rails reffiliate:generate  # Generate affiliate codes
docker-compose exec web rails spree_auth:admin:create  # Create admin user
```

## Deployment

### Heroku Deployment

The app uses **heroku ruby buildpack** on **heroku-20 stack**.

Key Heroku commands:
```bash
heroku run rake db:schema:load db:migrate -a dna-admin-staging
heroku run rake db:seed -a dna-admin-staging
heroku run rake spree_sample:load -a dna-admin-staging
heroku run rake assets:precompile -a dna-admin-staging
```

### Kubernetes Deployment

Configuration files:
- `k8-deployment.yaml` - Deployment configuration
- `k8-service.yml` - Service definition
- `k8-ingress.yml` - Ingress rules
- `secret.yaml.example` - Secret template
- `k8-deploy.sh` - Deployment script

## Important Notes

### Spree Customization
- Uses custom fork of Spree at `1instinct/spree` (instinct-dna branch)
- Never upgrade Spree without testing thoroughly
- Extensions are specifically versioned for Spree 4.2.x compatibility

### Active Storage
- Development uses local disk storage
- Production uses AWS S3
- Configure S3 credentials in environment variables

### CORS Configuration
- Wide-open CORS policy (`origins '*'`) in `config/initializers/cors.rb`
- Allows GET, POST, PATCH, PUT methods
- May need tightening for production security

### Authentication
- Admin: Devise-based username/password
- API: Token-based using `spree_api_key`
- API key passed in request headers or parameters

### Messaging System
- Polymorphic sender/receiver (can be any model)
- Auto-creates conversation threads
- Threads auto-archive after 7 days
- Integrates with external DNA API for SMS

### Live Streaming
- Integrates with Mux or similar service
- Supports product tagging in streams
- User likes and engagement tracking

## Code Style & Best Practices

### Ruby Style
- Use 2-space indentation
- Follow Ruby style guide conventions
- Use meaningful variable names
- Comment complex business logic

### Rails Conventions
- Fat models, skinny controllers
- Use concerns for shared behavior
- Service objects for complex business logic
- Keep controllers focused on HTTP concerns

### Database
- Always use migrations for schema changes
- Index foreign keys and frequently queried columns
- Use `acts_as_paranoid` for soft deletes where appropriate
- Leverage Ransack for search functionality

### API Design
- Use RESTful conventions
- Version APIs (currently v1)
- Return consistent JSON structures using Response concern
- Document all endpoints with Swagger
- Handle errors gracefully with appropriate HTTP status codes

### Security
- Never commit `.env` files
- Use environment variables for secrets
- Validate and sanitize user inputs
- Use strong parameters in controllers
- Implement proper authorization with CanCan

## Testing & Development

### Test Data
- **Factory Bot**: For creating test records
- **Faker**: For generating fake data
- **Spree Sample**: Sample products/data (`rails spree_sample:load`)

### Debugging
- Use `byebug` for debugging in development
- Check logs in `log/development.log`
- Rails console for interactive debugging

## Known Issues & Planned Improvements

### Menu Management System Issues
**Location**: `/admin/menu_items`

**Problems**:
- Edit template breaks when editing items with children
- Delete confirmation appears as a new element at the bottom of the page instead of a modal (easy to miss)
- Successfully editing a single item duplicates it at the root level

**Impact**: Menu hierarchy management is unreliable and can corrupt menu structure

### Homepage WYSIWYG Editor (Planned Feature)
**Similar to**: Live stream management pattern

**Requirements**:
- Create homepage content widgets/sections system
- Add "Homepage" sidebar item in admin with section editors
- Implement authenticated API endpoint for homepage content
- Allow editing of multiple content sections/widgets
- Follow the pattern used for live streams (custom admin controller + API v1 endpoint)

**Implementation Pattern**:
```ruby
# Admin: app/controllers/spree/admin/homepage_sections_controller.rb
# API: app/controllers/spree/api/v1/homepage_sections_controller.rb
# Model: app/models/homepage_section.rb
# Routes: Add to config/routes.rb under Spree::Core::Engine.add_routes
```

### Messages/Threads/Conversations System
**Location**: `/admin/messages`, `/admin/threads`

**Problems**:
- Three different views for the same data that don't work together cohesively
- No seed data for testing/development
- UI should be redesigned to iChat-style interface

**Requirements**:
- Create seed data for messages, threads, and conversations
- Consolidate three separate views into unified iChat-style UI
- Ensure message threading logic works consistently
- Improve conversation view to show real-time chat interface

**Current System**:
- Messages: Polymorphic sender/receiver
- ThreadTable: Groups messages between parties
- Auto-archives threads after 7 days of inactivity
- Integration with external DNA API for SMS

### Reporting Dashboard (Planned Feature)
**Location**: Admin dashboard

**Requirements**:
- Add graphs and charts for recent activity
- Track and visualize:
  - Orders (volume, revenue over time)
  - Contacts/Users (registrations, growth)
  - Messages (volume, response times)
- Consider using charting libraries (Chart.js, ApexCharts, or Chartkick gem)

**Implementation Considerations**:
- May need to add dashboard controller
- Create database queries/scopes for metrics
- Add date range filters
- Consider caching for performance

### WYSIWYG Editor Issues
**Location**: Rich text editor throughout admin

**Problems**:
- No icons displaying on editor buttons
- "Rich Editor" menu option exists but unclear purpose
- CKEditor displays security warning: "This CKEditor 4.11.3 version is not secure. Consider upgrading to the latest one, 4.25.1-lts"

**Affected by**: `spree_editor` gem from spree-contrib

**Options**:
1. Upgrade CKEditor to 4.25.1-lts (security fix)
2. Migrate to Trix editor (Rails default)
3. Migrate to ActionText (Rails 6 built-in)
4. Investigate spree_editor gem updates

**⚠️ Caution**: Editor change may affect existing content formatting

### Admin UI Layout Issue
**Location**: Top right corner of admin interface

**Problem**:
- Admin/user icon link displays strangely on desktop
- Erroneous link displays: `?class=logo+navbar-brand`
- Pushes account menu down inappropriately

**Likely Cause**: Incorrect link_to helper or partial rendering issue in admin layout

**Files to Check**:
- Admin layout partials (likely in Spree admin gem)
- May need decorator for admin layout

## When Suggesting Code

✅ **Do:**
- Use existing patterns from the codebase (decorators, services, concerns)
- Follow Spree conventions and override patterns
- Inherit from appropriate base classes (`Spree::Base`, `Spree::Admin::BaseController`)
- Include `Response` concern for API controllers
- Add Swagger documentation for API endpoints
- Use environment variables for configuration
- Implement proper authentication checks
- Use Ransack for search functionality
- Follow Rails conventions and best practices
- Use Docker commands for development tasks
- Reference known issues section when working on affected features
- Consider security implications (especially for CKEditor upgrade)

❌ **Don't:**
- Upgrade Ruby, Rails, or Spree versions
- Modify Spree core tables directly (use decorators)
- Hardcode configuration values
- Skip authentication on sensitive endpoints
- Forget to update Swagger documentation
- Bypass the Response concern for API responses
- Create migrations without proper indexing
- Ignore the existing hierarchical menu system patterns
- Modify the messaging/threading system without understanding its flow
- Break existing menu hierarchies when fixing menu management bugs