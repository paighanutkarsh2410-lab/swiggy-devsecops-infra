CREATE TABLE restaurants (
    id BIGSERIAL PRIMARY KEY,
    name VARCHAR(150) NOT NULL,
    description TEXT,
    address TEXT,
    cuisine VARCHAR(100),
    rating NUMERIC(2,1) CHECK (rating >= 0 AND rating <= 5),
    delivery_time_minutes INTEGER CHECK (delivery_time_minutes > 0),
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    -- Set by the restaurant from the partner console.
    is_open BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE menu_items (
    id BIGSERIAL PRIMARY KEY,
    restaurant_id BIGINT NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
    name VARCHAR(150) NOT NULL,
    description TEXT,
    price NUMERIC(10,2) NOT NULL CHECK (price >= 0),
    is_veg BOOLEAN NOT NULL DEFAULT TRUE,
    is_available BOOLEAN NOT NULL DEFAULT TRUE,
    -- Removed items stay in the table because past orders refer to them.
    is_archived BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- OWNER manages the restaurant and its menu. STAFF handles orders and can
-- mark items sold out. Both belong to exactly one restaurant.
CREATE TABLE users (
    id BIGSERIAL PRIMARY KEY,
    name VARCHAR(150) NOT NULL,
    email VARCHAR(254) NOT NULL UNIQUE,
    password_hash TEXT NOT NULL,
    role VARCHAR(20) NOT NULL DEFAULT 'CUSTOMER',
    restaurant_id BIGINT REFERENCES restaurants(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT users_role_check
        CHECK (role IN ('CUSTOMER', 'STAFF', 'OWNER')),
    CONSTRAINT users_restaurant_role_check
        CHECK ((role IN ('STAFF', 'OWNER')) = (restaurant_id IS NOT NULL))
);

CREATE TABLE orders (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT REFERENCES users(id),
    restaurant_id BIGINT NOT NULL REFERENCES restaurants(id),
    customer_name VARCHAR(150) NOT NULL,
    customer_address TEXT NOT NULL,
    total_amount NUMERIC(10,2) NOT NULL CHECK (total_amount >= 0),
    status VARCHAR(30) NOT NULL DEFAULT 'PLACED'
        CHECK (status IN (
            'PLACED',
            'CONFIRMED',
            'PREPARING',
            'OUT_FOR_DELIVERY',
            'DELIVERED',
            'CANCELLED'
        )),
    -- Set when the restaurant accepts the order.
    prep_minutes INTEGER CHECK (prep_minutes BETWEEN 5 AND 120),
    ready_by TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE order_items (
    id BIGSERIAL PRIMARY KEY,
    order_id BIGINT NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    menu_item_id BIGINT NOT NULL REFERENCES menu_items(id),
    quantity INTEGER NOT NULL CHECK (quantity > 0),
    unit_price NUMERIC(10,2) NOT NULL CHECK (unit_price >= 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_menu_items_restaurant_id
    ON menu_items(restaurant_id);

CREATE INDEX idx_orders_restaurant_id
    ON orders(restaurant_id);

CREATE INDEX idx_orders_user_id
    ON orders(user_id);

CREATE INDEX idx_orders_status
    ON orders(status);

CREATE INDEX idx_order_items_order_id
    ON order_items(order_id);

-- Every new order and status change is announced on the order_events
-- channel. Each API instance listens and pushes the event to the partner
-- consoles of that restaurant, so it works with more than one replica.
CREATE OR REPLACE FUNCTION notify_order_event() RETURNS trigger AS $$
BEGIN
    PERFORM pg_notify(
        'order_events',
        json_build_object(
            'type', CASE WHEN TG_OP = 'INSERT' THEN 'order_created' ELSE 'order_updated' END,
            'order_id', NEW.id::text,
            'restaurant_id', NEW.restaurant_id::text,
            'status', NEW.status
        )::text
    );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER orders_notify_event
    AFTER INSERT OR UPDATE OF status ON orders
    FOR EACH ROW EXECUTE FUNCTION notify_order_event();

INSERT INTO restaurants (
    name,
    description,
    address,
    cuisine,
    rating,
    delivery_time_minutes
)
VALUES
(
    'Spice Garden',
    'Authentic Indian cuisine with rich flavors.',
    'Nagpur',
    'Indian',
    4.5,
    35
),
(
    'Pizza Hub',
    'Freshly baked pizzas and sides.',
    'Nagpur',
    'Italian',
    4.2,
    30
);

INSERT INTO menu_items (
    restaurant_id,
    name,
    description,
    price,
    is_veg
)
VALUES
(1, 'Paneer Butter Masala', 'Creamy paneer curry', 249.00, TRUE),
(1, 'Dal Tadka', 'Yellow lentils tempered with spices', 179.00, TRUE),
(1, 'Chicken Biryani', 'Aromatic chicken biryani', 299.00, FALSE),
(2, 'Margherita Pizza', 'Classic tomato and mozzarella pizza', 299.00, TRUE),
(2, 'Farmhouse Pizza', 'Loaded vegetable pizza', 399.00, TRUE);
