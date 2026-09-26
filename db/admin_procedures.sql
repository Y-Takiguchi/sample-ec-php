-- =====================================================================
-- 手動運用用: 在庫操作・新規登録のストアドプロシージャ
--
-- 管理画面・APIを経由せず、docker compose exec から直接DBを操作するための
-- プロシージャ群です。triggers.sql とは独立しており、トリガーは作成しません
-- （このファイルだけを適用しても、API経由の注文で在庫が二重に減ることはありません）。
--
-- 適用方法:
--   docker compose exec -T db psql -U postgres -d sample_ec -f - < db/admin_procedures.sql
--
-- 呼び出し方法（例）:
--   docker compose exec db psql -U postgres -d sample_ec -c "CALL sp_receive_stock(1, 20);"
--
-- 各プロシージャは処理結果を NOTICE で表示し、不正な入力の場合は
-- RAISE EXCEPTION で中断します（CALL全体がロールバックされます）。
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. 商品の新規登録
--    初期在庫が1以上の場合は stock_logs に reason = 'initial' で記録する。
--
-- 呼び出し例:
--   CALL sp_register_product('ワイヤレス充電器', 3280, 30, 'PCアクセサリ');
--   CALL sp_register_product('加湿器', 7980, 10, '生活家電', 15);  -- 割引率15%
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_register_product(
    p_name     VARCHAR,
    p_price    NUMERIC,
    p_stock    INT     DEFAULT 0,
    p_category VARCHAR DEFAULT NULL,
    p_discount NUMERIC DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_product_id INT;
BEGIN
    IF p_name IS NULL OR btrim(p_name) = '' THEN
        RAISE EXCEPTION '商品名を指定してください';
    END IF;

    IF p_price IS NULL OR p_price < 0 THEN
        RAISE EXCEPTION '価格は0以上で指定してください（指定値: %）', p_price;
    END IF;

    IF p_stock IS NULL OR p_stock < 0 THEN
        RAISE EXCEPTION '初期在庫は0以上で指定してください（指定値: %）', p_stock;
    END IF;

    IF p_discount IS NOT NULL AND (p_discount < 0 OR p_discount > 100) THEN
        RAISE EXCEPTION '割引率は0〜100で指定してください（指定値: %）', p_discount;
    END IF;

    INSERT INTO products (name, price, stock, category, discount_percentage, created_at, updated_at)
    VALUES (p_name, p_price, p_stock, p_category, p_discount, NOW(), NOW())
    RETURNING id INTO v_product_id;

    IF p_stock > 0 THEN
        INSERT INTO stock_logs (product_id, change, reason, created_at)
        VALUES (v_product_id, p_stock, 'initial', NOW());
    END IF;

    RAISE NOTICE '商品を登録しました（ID: %, 商品名: %, 価格: %, 在庫: %）',
        v_product_id, p_name, p_price, p_stock;
END;
$$;

-- ---------------------------------------------------------------------
-- 2. 仕入れ（入荷）登録
--    管理画面の「入荷登録」と同じく、在庫を加算し reason = 'purchase' で記録する。
--
-- 呼び出し例:
--   CALL sp_receive_stock(7, 20);  -- 商品ID=7 を20個入荷
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_receive_stock(
    p_product_id INT,
    p_quantity   INT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_stock INT;
BEGIN
    IF p_quantity IS NULL OR p_quantity <= 0 THEN
        RAISE EXCEPTION '入荷数量は1以上で指定してください（指定値: %）', p_quantity;
    END IF;

    SELECT stock INTO v_stock FROM products WHERE id = p_product_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION '商品が見つかりません（ID: %）', p_product_id;
    END IF;

    UPDATE products
    SET stock = stock + p_quantity,
        updated_at = NOW()
    WHERE id = p_product_id;

    INSERT INTO stock_logs (product_id, change, reason, created_at)
    VALUES (p_product_id, p_quantity, 'purchase', NOW());

    RAISE NOTICE '入荷を登録しました（商品ID: %, 在庫: % → %）',
        p_product_id, v_stock, v_stock + p_quantity;
END;
$$;

-- ---------------------------------------------------------------------
-- 3. 在庫の調整（棚卸差異・破損・返品など）
--    増減数を指定して在庫を補正する。調整後の在庫がマイナスになる場合は中断する。
--
-- 呼び出し例:
--   CALL sp_adjust_stock(3, -2);              -- 破損などで2個減らす（reason = 'adjustment'）
--   CALL sp_adjust_stock(3, 1, 'return');     -- 返品で1個戻す
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_adjust_stock(
    p_product_id INT,
    p_change     INT,
    p_reason     VARCHAR DEFAULT 'adjustment'
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_stock INT;
BEGIN
    IF p_change IS NULL OR p_change = 0 THEN
        RAISE EXCEPTION '増減数は0以外で指定してください';
    END IF;

    IF p_reason IS NULL OR btrim(p_reason) = '' THEN
        RAISE EXCEPTION '調整理由を指定してください';
    END IF;

    SELECT stock INTO v_stock FROM products WHERE id = p_product_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION '商品が見つかりません（ID: %）', p_product_id;
    END IF;

    IF v_stock + p_change < 0 THEN
        RAISE EXCEPTION '在庫がマイナスになるため調整できません（商品ID: %, 在庫: %, 増減: %）',
            p_product_id, v_stock, p_change;
    END IF;

    UPDATE products
    SET stock = stock + p_change,
        updated_at = NOW()
    WHERE id = p_product_id;

    INSERT INTO stock_logs (product_id, change, reason, created_at)
    VALUES (p_product_id, p_change, p_reason, NOW());

    RAISE NOTICE '在庫を調整しました（商品ID: %, 在庫: % → %, 理由: %）',
        p_product_id, v_stock, v_stock + p_change, p_reason;
END;
$$;

-- ---------------------------------------------------------------------
-- 4. 顧客の新規登録
--    APIに顧客作成エンドポイントが無いため、Seeder以外で顧客を追加する手段として使う。
--
-- 呼び出し例:
--   CALL sp_register_customer('山田 花子', 'hanako@example.com');
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_register_customer(
    p_name  VARCHAR,
    p_email VARCHAR
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_customer_id INT;
BEGIN
    IF p_name IS NULL OR btrim(p_name) = '' THEN
        RAISE EXCEPTION '顧客名を指定してください';
    END IF;

    IF p_email IS NULL OR btrim(p_email) = '' THEN
        RAISE EXCEPTION 'メールアドレスを指定してください';
    END IF;

    IF EXISTS (SELECT 1 FROM customers WHERE email = p_email) THEN
        RAISE EXCEPTION 'このメールアドレスは既に登録されています: %', p_email;
    END IF;

    INSERT INTO customers (name, email, created_at, updated_at)
    VALUES (p_name, p_email, NOW(), NOW())
    RETURNING id INTO v_customer_id;

    RAISE NOTICE '顧客を登録しました（ID: %, 氏名: %, メール: %）',
        v_customer_id, p_name, p_email;
END;
$$;
