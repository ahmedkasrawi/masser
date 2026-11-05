-- ==============================================================================
-- منصة مسار للاستشارات (Masser Platform)
-- Database Schema (PostgreSQL DDL)
-- Version: 1.0
-- Architecture: Next.js + Node.js + PostgreSQL
-- ==============================================================================

-- تفعيل امتداد UUID لإنشاء معرفات فريدة وآمنة
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ==============================================================================
-- 1. أنواع البيانات المخصصة (Custom ENUM Types)
-- ==============================================================================

CREATE TYPE user_role AS ENUM ('client', 'expert', 'admin', 'staff');
CREATE TYPE gender_type AS ENUM ('male', 'female');
CREATE TYPE verification_status AS ENUM ('pending', 'approved', 'rejected');
CREATE TYPE booking_status AS ENUM (
    'pending_payment',
    'confirmed',
    'in_progress',
    'completed',
    'cancelled',
    'no_show'
);
CREATE TYPE payment_status AS ENUM ('pending', 'paid', 'failed', 'refunded');
CREATE TYPE escrow_status AS ENUM ('holding', 'released', 'disputed', 'refunded');
CREATE TYPE meeting_provider AS ENUM ('google_meet', 'zoom');
CREATE TYPE payout_status AS ENUM ('pending', 'approved', 'rejected', 'transferred');
CREATE TYPE notification_type AS ENUM (
    'booking_confirmation',
    'session_reminder_24h',
    'session_reminder_1h',
    'session_reminder_15m',
    'early_access_available',
    'payout_update',
    'system_announcement'
);

-- ==============================================================================
-- 2. جدول المستخدمين الأساسي (Users)
-- ==============================================================================
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255), -- اختياري في حال استخدام Google Auth
    full_name VARCHAR(150) NOT NULL,
    phone_number VARCHAR(30),
    role user_role DEFAULT 'client' NOT NULL,
    avatar_url TEXT,
    timezone VARCHAR(50) DEFAULT 'Asia/Riyadh' NOT NULL,
    is_verified BOOLEAN DEFAULT FALSE NOT NULL,
    google_id VARCHAR(255) UNIQUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL
);

-- ==============================================================================
-- 3. جدول تفضيلات الحساب والتهيئة (User Preferences - اختياري بعد التسجيل)
-- ==============================================================================
CREATE TABLE user_preferences (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    field_of_interest VARCHAR(100),
    gender gender_type,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT uq_user_preferences UNIQUE (user_id)
);

-- ==============================================================================
-- 4. جدول التحقق برمز مؤقت (OTP Codes)
-- ==============================================================================
CREATE TABLE user_otps (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email VARCHAR(255) NOT NULL,
    otp_code VARCHAR(10) NOT NULL,
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    is_used BOOLEAN DEFAULT FALSE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL
);

-- ==============================================================================
-- 5. جدول ملفات الخبراء (Expert Profiles)
-- ==============================================================================
CREATE TABLE expert_profiles (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    headline VARCHAR(200),
    bio TEXT,
    is_verified_expert BOOLEAN DEFAULT FALSE NOT NULL, -- شارة التوثيق المعتمدة
    verification_status verification_status DEFAULT 'pending' NOT NULL,
    rejection_reason TEXT,
    documents_url TEXT[], -- روابط الشهادات وتراخيص العمل
    rating_avg NUMERIC(3, 2) DEFAULT 0.00 NOT NULL,
    reviews_count INT DEFAULT 0 NOT NULL,
    total_consultations_count INT DEFAULT 0 NOT NULL,
    -- البيانات البنكية للتحويل
    bank_name VARCHAR(100),
    iban VARCHAR(50),
    account_holder_name VARCHAR(150),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT uq_expert_user UNIQUE (user_id)
);

-- ==============================================================================
-- 6. جدول خدمات واستشارات الخبير (Consultation Services)
-- ==============================================================================
CREATE TABLE consultation_services (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    expert_id UUID NOT NULL REFERENCES expert_profiles(id) ON DELETE CASCADE,
    title VARCHAR(150) NOT NULL,
    description TEXT,
    duration_minutes INT NOT NULL, -- مثلاً 30، 45، 60 دقيقة
    price NUMERIC(10, 2) NOT NULL,
    currency VARCHAR(10) DEFAULT 'SAR' NOT NULL,
    is_active BOOLEAN DEFAULT TRUE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL
);

-- ==============================================================================
-- 7. جدول فترات العمل المتاحة للخبير (Availability Slots)
-- ==============================================================================
CREATE TABLE availability_slots (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    expert_id UUID NOT NULL REFERENCES expert_profiles(id) ON DELETE CASCADE,
    day_of_week SMALLINT NOT NULL CHECK (day_of_week BETWEEN 0 AND 6), -- 0=الأحد إلى 6=السبت
    start_time TIME NOT NULL,
    end_time TIME NOT NULL,
    is_active BOOLEAN DEFAULT TRUE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT chk_time_order CHECK (end_time > start_time)
);

-- ==============================================================================
-- 8. جدول الحجوزات (Bookings)
-- ==============================================================================
CREATE TABLE bookings (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    booking_reference VARCHAR(20) UNIQUE NOT NULL, -- كود مرجعي مثل MSSR-84920
    client_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    expert_id UUID NOT NULL REFERENCES expert_profiles(id) ON DELETE RESTRICT,
    service_id UUID NOT NULL REFERENCES consultation_services(id) ON DELETE RESTRICT,
    scheduled_start TIMESTAMP WITH TIME ZONE NOT NULL,
    scheduled_end TIMESTAMP WITH TIME ZONE NOT NULL,
    client_timezone VARCHAR(50) NOT NULL,
    status booking_status DEFAULT 'pending_payment' NOT NULL,
    
    -- بيانات اجتماع الفيديو الخارجي (Google Meet / Zoom)
    meeting_provider meeting_provider DEFAULT 'google_meet' NOT NULL,
    meeting_join_url TEXT,
    meeting_host_url TEXT,
    
    -- موجز ومرفقات ما قبل الجلسة (Pre-session Briefing)
    client_brief_notes TEXT,
    attachment_url TEXT,
    
    -- سياسة الإلغاء وعدم الحضور
    cancellation_reason TEXT,
    cancelled_by UUID REFERENCES users(id),
    cancelled_at TIMESTAMP WITH TIME ZONE,
    
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL
);

-- ==============================================================================
-- 9. جدول المدفوعات ونظام الأمان المالي 80/20 (Payments & Escrow)
-- ==============================================================================
CREATE TABLE payments (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    booking_id UUID NOT NULL REFERENCES bookings(id) ON DELETE RESTRICT,
    amount_total NUMERIC(10, 2) NOT NULL,
    platform_fee NUMERIC(10, 2) NOT NULL, -- 20% عمولة المنصة
    expert_earnings NUMERIC(10, 2) NOT NULL, -- 80% أرباح الخبير
    currency VARCHAR(10) DEFAULT 'SAR' NOT NULL,
    
    payment_status payment_status DEFAULT 'pending' NOT NULL,
    gateway_name VARCHAR(50) NOT NULL, -- e.g. Moyasar, Tap, Stripe
    gateway_transaction_id VARCHAR(255),
    
    -- نظام تعليق الرصيد (Escrow Holding 24-48h)
    escrow_status escrow_status DEFAULT 'holding' NOT NULL,
    escrow_release_due_at TIMESTAMP WITH TIME ZONE NOT NULL, -- وقت فك الحجز التلقائي بعد 48 ساعة
    escrow_released_at TIMESTAMP WITH TIME ZONE,
    
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT uq_payment_booking UNIQUE (booking_id)
);

-- ==============================================================================
-- 10. جدول طلبات سحب الأرباح للخبراء (Payout Requests)
-- ==============================================================================
CREATE TABLE payout_requests (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    expert_id UUID NOT NULL REFERENCES expert_profiles(id) ON DELETE RESTRICT,
    amount NUMERIC(10, 2) NOT NULL CHECK (amount >= 200.00), -- الحد الأدنى للسحب 200 ريال / 50 دولار
    currency VARCHAR(10) DEFAULT 'SAR' NOT NULL,
    status payout_status DEFAULT 'pending' NOT NULL,
    bank_reference_number VARCHAR(100),
    requested_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    processed_at TIMESTAMP WITH TIME ZONE,
    processed_by UUID REFERENCES users(id) -- المشرف المالي
);

-- ==============================================================================
-- 11. جدول "سجل اهتمامك" وأسبقية الحجز (Express Interest & Early Access)
-- ==============================================================================
CREATE TABLE express_interests (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    client_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    expert_id UUID NOT NULL REFERENCES expert_profiles(id) ON DELETE CASCADE,
    preferred_time_notes TEXT,
    early_access_token UUID DEFAULT uuid_generate_v4() NOT NULL,
    early_access_expires_at TIMESTAMP WITH TIME ZONE, -- ينتهي بعد ساعتين من إرسال الإشعار
    is_notified BOOLEAN DEFAULT FALSE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL
);

-- ==============================================================================
-- 12. جدول التقييمات وملاحظات المنصة (Reviews & Platform Feedback)
-- ==============================================================================
CREATE TABLE reviews (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    booking_id UUID NOT NULL REFERENCES bookings(id) ON DELETE RESTRICT,
    client_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    expert_id UUID NOT NULL REFERENCES expert_profiles(id) ON DELETE RESTRICT,
    rating SMALLINT NOT NULL CHECK (rating BETWEEN 1 AND 5),
    expert_comment TEXT,
    platform_feedback TEXT, -- ملاحظات خاصة للإدارة لتحسين جودة المنصة
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT uq_review_booking UNIQUE (booking_id)
);

-- ==============================================================================
-- 13. جدول الإشعارات الداخلية (In-App Notifications)
-- ==============================================================================
CREATE TABLE in_app_notifications (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    title VARCHAR(150) NOT NULL,
    body TEXT NOT NULL,
    action_url TEXT,
    notification_type notification_type NOT NULL,
    is_read BOOLEAN DEFAULT FALSE NOT NULL,
    read_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL
);

-- ==============================================================================
-- 14. جدول صلاحيات موظفي الإدارة (Staff Permissions - RBAC)
-- ==============================================================================
CREATE TABLE staff_permissions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    module VARCHAR(50) NOT NULL, -- e.g. 'experts', 'payments', 'bookings', 'reports'
    can_read BOOLEAN DEFAULT TRUE NOT NULL,
    can_write BOOLEAN DEFAULT FALSE NOT NULL,
    can_delete BOOLEAN DEFAULT FALSE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT uq_staff_module UNIQUE (user_id, module)
);

-- ==============================================================================
-- 15. الفهارس لتسريع الاستعلامات والأداء (Performance Indexes)
-- ==============================================================================
CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_role ON users(role);
CREATE INDEX idx_expert_profiles_status ON expert_profiles(verification_status, is_verified_expert);
CREATE INDEX idx_bookings_client ON bookings(client_id);
CREATE INDEX idx_bookings_expert ON bookings(expert_id);
CREATE INDEX idx_bookings_start ON bookings(scheduled_start);
CREATE INDEX idx_bookings_status ON bookings(status);
CREATE INDEX idx_payments_escrow ON payments(escrow_status, escrow_release_due_at);
CREATE INDEX idx_notifications_user_unread ON in_app_notifications(user_id, is_read);
CREATE INDEX idx_availability_expert_day ON availability_slots(expert_id, day_of_week);
CREATE INDEX idx_express_interests_expert ON express_interests(expert_id, is_notified);
