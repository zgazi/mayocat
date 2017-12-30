--
-- PostgreSQL database dump
--

-- Dumped from database version 9.6.6
-- Dumped by pg_dump version 9.6.6


--
-- Name: dbo; Type: SCHEMA; Schema: -; Owner: mayocat
--

CREATE SCHEMA dbo;


ALTER SCHEMA dbo OWNER TO mayocat;

--
-- Name: plpgsql; Type: EXTENSION; Schema: -; Owner: 
--

CREATE EXTENSION IF NOT EXISTS plpgsql WITH SCHEMA pg_catalog;


--
-- Name: EXTENSION plpgsql; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION plpgsql IS 'PL/pgSQL procedural language';


--
-- Name: pg_trgm; Type: EXTENSION; Schema: -; Owner: 
--

CREATE EXTENSION IF NOT EXISTS pg_trgm WITH SCHEMA dbo;


--
-- Name: EXTENSION pg_trgm; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION pg_trgm IS 'text similarity measurement and index searching based on trigrams';


--
-- Name: unaccent; Type: EXTENSION; Schema: -; Owner: 
--

CREATE EXTENSION IF NOT EXISTS unaccent WITH SCHEMA dbo;


--
-- Name: EXTENSION unaccent; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION unaccent IS 'text search dictionary that removes accents';


SET search_path = dbo, pg_catalog;

--
-- Name: localized_entity; Type: TABLE; Schema: dbo; Owner: mayocat
--

CREATE TABLE localized_entity (
    entity_id uuid,
    locale character varying(5),
    entity json
);


ALTER TABLE localized_entity OWNER TO mayocat;

--
-- Name: page; Type: TABLE; Schema: dbo; Owner: mayocat
--

--
-- Name: insert_child_entity_if_not_exist(uuid, character varying, character varying, uuid, uuid); Type: FUNCTION; Schema: dbo; Owner: mayocat
--

CREATE FUNCTION insert_child_entity_if_not_exist(in_entity_id uuid, in_slug character varying, in_type character varying, in_entity_tenant uuid, in_entity_parent uuid) RETURNS integer
    LANGUAGE plpgsql
    AS $$
BEGIN
  BEGIN
    INSERT INTO entity (id, slug, type, tenant_id, parent_id) VALUES (in_entity_id, in_slug, in_type, in_entity_tenant, in_entity_parent);
      RETURN (SELECT 1);
    EXCEPTION WHEN OTHERS
    THEN
      RETURN (SELECT 0);
  END;
END;
$$;


ALTER FUNCTION dbo.insert_child_entity_if_not_exist(in_entity_id uuid, in_slug character varying, in_type character varying, in_entity_tenant uuid, in_entity_parent uuid) OWNER TO mayocat;

--
-- Name: insert_entity_if_not_exist(uuid, character varying, character varying, uuid); Type: FUNCTION; Schema: dbo; Owner: mayocat
--

CREATE FUNCTION insert_entity_if_not_exist(in_entity_id uuid, in_slug character varying, in_type character varying, in_entity_tenant uuid) RETURNS integer
    LANGUAGE plpgsql
    AS $$
BEGIN
  BEGIN
    INSERT INTO entity (id, slug, type, tenant_id) VALUES (in_entity_id, in_slug, in_type, in_entity_tenant);
      RETURN (SELECT 1);
    EXCEPTION WHEN OTHERS
    THEN
      RETURN (SELECT 0);
  END;
END;
$$;


ALTER FUNCTION dbo.insert_entity_if_not_exist(in_entity_id uuid, in_slug character varying, in_type character varying, in_entity_tenant uuid) OWNER TO mayocat;

--
-- Name: json_object_set_key(json, text, anyelement); Type: FUNCTION; Schema: dbo; Owner: mayocat
--

CREATE FUNCTION json_object_set_key(json json, key_to_set text, value_to_set anyelement) RETURNS json
    LANGUAGE sql IMMUTABLE STRICT
    AS $$
SELECT COALESCE(
  (SELECT ('{' || string_agg(to_json("key") || ':' || "value", ',') || '}')
     FROM (SELECT *
             FROM json_each("json")
            WHERE "key" <> "key_to_set"
            UNION ALL
           SELECT "key_to_set", to_json("value_to_set")) AS "fields"),
  '{}'
)::json
$$;


ALTER FUNCTION dbo.json_object_set_key(json json, key_to_set text, value_to_set anyelement) OWNER TO mayocat;

--
-- Name: localization_data(uuid); Type: FUNCTION; Schema: dbo; Owner: mayocat
--

CREATE FUNCTION localization_data(the_entity_id uuid) RETURNS json
    LANGUAGE sql
    AS $$
  SELECT array_to_json(array_agg(row_to_json(l)))
  FROM (
      SELECT locale, entity
      FROM localized_entity
      WHERE localized_entity.entity_id = the_entity_id
  ) l
$$;


ALTER FUNCTION dbo.localization_data(the_entity_id uuid) OWNER TO mayocat;

--
-- Name: m_unaccent(text); Type: FUNCTION; Schema: dbo; Owner: mayocat
--

CREATE FUNCTION m_unaccent(text) RETURNS text
    LANGUAGE sql IMMUTABLE
    SET search_path TO dbo, pg_temp
    AS $_$
SELECT unaccent('unaccent', $1)
$_$;


ALTER FUNCTION dbo.m_unaccent(text) OWNER TO mayocat;

--
-- Name: upsert_translation(uuid, text, json); Type: FUNCTION; Schema: dbo; Owner: mayocat
--

CREATE FUNCTION upsert_translation(in_entity_id uuid, in_locale text, in_entity json) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
    UPDATE localized_entity set entity = in_entity WHERE entity_id = in_entity_id and locale = in_locale;
    IF FOUND THEN
        RETURN;
    END IF;
    BEGIN
        INSERT INTO localized_entity (entity_id, locale, entity) values (in_entity_id, in_locale, in_entity);
    EXCEPTION WHEN OTHERS THEN
        UPDATE localized_entity set entity = in_entity WHERE entity_id = in_entity_id and locale = in_locale;
    END;
    RETURN;
END;
$$;


ALTER FUNCTION dbo.upsert_translation(in_entity_id uuid, in_locale text, in_entity json) OWNER TO mayocat;

--
-- Name: json_object_agg(text, anyelement); Type: AGGREGATE; Schema: dbo; Owner: mayocat
--

CREATE AGGREGATE json_object_agg(text, anyelement) (
    SFUNC = json_object_set_key,
    STYPE = json,
    INITCOND = '{}'
);


ALTER AGGREGATE dbo.json_object_agg(text, anyelement) OWNER TO mayocat;

--
-- Name: _uuid_ops; Type: OPERATOR FAMILY; Schema: dbo; Owner: mayocat
--

CREATE OPERATOR FAMILY _uuid_ops USING gin;


ALTER OPERATOR FAMILY dbo._uuid_ops USING gin OWNER TO mayocat;

--
-- Name: _uuid_ops; Type: OPERATOR CLASS; Schema: dbo; Owner: mayocat
--

CREATE OPERATOR CLASS _uuid_ops
    DEFAULT FOR TYPE uuid[] USING gin FAMILY _uuid_ops AS
    STORAGE uuid ,
    OPERATOR 1 &&(anyarray,anyarray) ,
    OPERATOR 2 @>(anyarray,anyarray) ,
    OPERATOR 3 <@(anyarray,anyarray) ,
    OPERATOR 4 =(anyarray,anyarray) ,
    FUNCTION 1 (uuid[], uuid[]) uuid_cmp(uuid,uuid) ,
    FUNCTION 2 (uuid[], uuid[]) ginarrayextract(anyarray,internal,internal) ,
    FUNCTION 3 (uuid[], uuid[]) ginqueryarrayextract(anyarray,internal,smallint,internal,internal,internal,internal) ,
    FUNCTION 4 (uuid[], uuid[]) ginarrayconsistent(internal,smallint,anyarray,integer,internal,internal,internal,internal);


ALTER OPERATOR CLASS dbo._uuid_ops USING gin OWNER TO mayocat;

SET default_tablespace = '';

SET default_with_oids = false;

--
-- Name: addon; Type: TABLE; Schema: dbo; Owner: mayocat
--

CREATE TABLE addon (
    entity_id uuid,
    source character varying(255),
    addon_group character varying(255),
    model json,
    value json
);


ALTER TABLE addon OWNER TO mayocat;

--
-- Name: address; Type: TABLE; Schema: dbo; Owner: mayocat
--

CREATE TABLE address (
    address_id uuid NOT NULL,
    customer_id uuid,
    company character varying(255),
    full_name character varying(255),
    street character varying(255),
    street_complement character varying(255),
    zip character varying(255),
    city character varying(255),
    country character varying(255)
);


ALTER TABLE address OWNER TO mayocat;

--
-- Name: agent; Type: TABLE; Schema: dbo; Owner: mayocat
--

CREATE TABLE agent (
    entity_id uuid NOT NULL,
    email character varying(255) NOT NULL,
    password character varying(255)
);


ALTER TABLE agent OWNER TO mayocat;

--
-- Name: agent_role; Type: TABLE; Schema: dbo; Owner: mayocat
--

CREATE TABLE agent_role (
    agent_id uuid NOT NULL,
    role character varying(255) NOT NULL
);


ALTER TABLE agent_role OWNER TO mayocat;

--
-- Name: article; Type: TABLE; Schema: dbo; Owner: mayocat
--

CREATE TABLE article (
    entity_id uuid NOT NULL,
    model character varying(255),
    published boolean,
    publication_date timestamp with time zone,
    title character varying(255),
    content text,
    featured_image_id uuid
);


ALTER TABLE article OWNER TO mayocat;

--
-- Name: attachment; Type: TABLE; Schema: dbo; Owner: mayocat
--

CREATE TABLE attachment (
    entity_id uuid NOT NULL,
    extension character varying(255) NOT NULL,
    title character varying(255),
    description text,
    data bytea,
    metadata json
);


ALTER TABLE attachment OWNER TO mayocat;

--
-- Name: carrier; Type: TABLE; Schema: dbo; Owner: mayocat
--

CREATE TABLE carrier (
    tenant_id uuid,
    id uuid NOT NULL,
    destinations text,
    title character varying(255),
    strategy character varying(255),
    description text,
    minimum_days smallint,
    maximum_days smallint,
    per_shipping numeric(18,4),
    per_item numeric(18,4),
    per_additional_unit numeric(18,4)
);


ALTER TABLE carrier OWNER TO mayocat;

--
-- Name: carrier_rule; Type: TABLE; Schema: dbo; Owner: mayocat
--

CREATE TABLE carrier_rule (
    carrier_id uuid NOT NULL,
    up_to_value numeric(18,4),
    price numeric(18,4)
);


ALTER TABLE carrier_rule OWNER TO mayocat;

--
-- Name: collection; Type: TABLE; Schema: dbo; Owner: mayocat
--

CREATE TABLE collection (
    entity_id uuid NOT NULL,
    model character varying(255),
    "position" smallint,
    title character varying(255),
    description text,
    featured_image_id uuid
);


ALTER TABLE collection OWNER TO mayocat;

--
-- Name: collection_product; Type: TABLE; Schema: dbo; Owner: mayocat
--

CREATE TABLE collection_product (
    collection_id uuid NOT NULL,
    product_id uuid NOT NULL,
    "position" smallint
);


ALTER TABLE collection_product OWNER TO mayocat;

--
-- Name: customer; Type: TABLE; Schema: dbo; Owner: mayocat
--

CREATE TABLE customer (
    entity_id uuid NOT NULL,
    email character varying(255),
    first_name character varying(255),
    last_name character varying(255),
    phone_number character varying(255)
);


ALTER TABLE customer OWNER TO mayocat;

--
-- Name: entity; Type: TABLE; Schema: dbo; Owner: mayocat
--

CREATE TABLE entity (
    id uuid NOT NULL,
    slug character varying(255) NOT NULL,
    type character varying(255) NOT NULL,
    tenant_id uuid,
    parent_id uuid
);


ALTER TABLE entity OWNER TO mayocat;

--
-- Name: entity_list; Type: TABLE; Schema: dbo; Owner: mayocat
--

CREATE TABLE entity_list (
    entity_id uuid,
    entity_type character varying(255),
    entities uuid[],
    hint character varying(255)
);


ALTER TABLE entity_list OWNER TO mayocat;

--
-- Name: gateway_customer_data; Type: TABLE; Schema: dbo; Owner: mayocat
--

CREATE TABLE gateway_customer_data (
    customer_id uuid NOT NULL,
    gateway character varying(255),
    customer_data text
);


ALTER TABLE gateway_customer_data OWNER TO mayocat;

--
-- Name: gateway_tenant_data; Type: TABLE; Schema: dbo; Owner: mayocat
--

CREATE TABLE gateway_tenant_data (
    tenant_id uuid NOT NULL,
    gateway character varying(255),
    tenant_data text
);


ALTER TABLE gateway_tenant_data OWNER TO mayocat;


CREATE TABLE page (
    entity_id uuid NOT NULL,
    model character varying(255),
    published boolean,
    "position" smallint,
    title character varying(255),
    content text,
    featured_image_id uuid
);


ALTER TABLE page OWNER TO mayocat;

--
-- Name: payment_operation; Type: TABLE; Schema: dbo; Owner: mayocat
--

CREATE TABLE payment_operation (
    operation_id uuid NOT NULL,
    order_id uuid,
    gateway_id character varying(255),
    external_id character varying(255),
    result character varying(255),
    memo text
);


ALTER TABLE payment_operation OWNER TO mayocat;

--
-- Name: product; Type: TABLE; Schema: dbo; Owner: mayocat
--

CREATE TABLE product (
    entity_id uuid NOT NULL,
    model character varying(255),
    on_shelf boolean,
    "position" smallint,
    title character varying(255),
    description text,
    price numeric(18,4),
    stock smallint,
    featured_image_id uuid,
    weight numeric,
    product_type character varying(255),
    virtual boolean DEFAULT false NOT NULL,
    features uuid[]
);


ALTER TABLE product OWNER TO mayocat;

--
-- Name: product_feature; Type: TABLE; Schema: dbo; Owner: mayocat
--

CREATE TABLE product_feature (
    entity_id uuid NOT NULL,
    feature character varying(255),
    feature_slug character varying(255),
    title character varying(255)
);


ALTER TABLE product_feature OWNER TO mayocat;

--
-- Name: purchase_order; Type: TABLE; Schema: dbo; Owner: mayocat
--

CREATE TABLE purchase_order (
    entity_id uuid NOT NULL,
    customer_id uuid,
    delivery_address_id uuid,
    billing_address_id uuid,
    creation_date timestamp with time zone,
    update_date timestamp with time zone,
    currency character varying(3),
    number_of_items smallint,
    items_total numeric(18,4),
    grand_total numeric(18,4),
    status character varying(32),
    order_data text,
    shipping numeric(18,4),
    additional_information text
);


ALTER TABLE purchase_order OWNER TO mayocat;

--
-- Name: schema_version; Type: TABLE; Schema: dbo; Owner: mayocat
--

CREATE TABLE schema_version (
    version_rank integer NOT NULL,
    installed_rank integer NOT NULL,
    version character varying(50) NOT NULL,
    description character varying(200) NOT NULL,
    type character varying(20) NOT NULL,
    script character varying(1000) NOT NULL,
    checksum integer,
    installed_by character varying(100) NOT NULL,
    installed_on timestamp without time zone DEFAULT now() NOT NULL,
    execution_time integer NOT NULL,
    success boolean NOT NULL
);


ALTER TABLE schema_version OWNER TO mayocat;

--
-- Name: tenant; Type: TABLE; Schema: dbo; Owner: mayocat
--

CREATE TABLE tenant (
    entity_id uuid NOT NULL,
    default_host character varying(255),
    configuration text,
    configuration_version smallint,
    name character varying(255),
    creation_date timestamp without time zone,
    featured_image_id uuid,
    contact_email character varying(255),
    description text
);


ALTER TABLE tenant OWNER TO mayocat;

--
-- Name: thumbnail; Type: TABLE; Schema: dbo; Owner: mayocat
--

CREATE TABLE thumbnail (
    attachment_id uuid NOT NULL,
    source character varying(255) NOT NULL,
    hint character varying(255) NOT NULL,
    ratio character varying(255),
    x integer,
    y integer,
    width integer,
    height integer
);


ALTER TABLE thumbnail OWNER TO mayocat;


--
-- Name: addon addon_unique_group_per_source_per_entity; Type: CONSTRAINT; Schema: dbo; Owner: mayocat
--

ALTER TABLE ONLY addon
    ADD CONSTRAINT addon_unique_group_per_source_per_entity UNIQUE (entity_id, source, addon_group);


--
-- Name: collection_product collection_product_pk; Type: CONSTRAINT; Schema: dbo; Owner: mayocat
--

ALTER TABLE ONLY collection_product
    ADD CONSTRAINT collection_product_pk PRIMARY KEY (collection_id, product_id);


--
-- Name: entity entity_unique_slug_per_type_per_parent_per_tenant; Type: CONSTRAINT; Schema: dbo; Owner: mayocat
--

ALTER TABLE ONLY entity
    ADD CONSTRAINT entity_unique_slug_per_type_per_parent_per_tenant UNIQUE (slug, type, tenant_id, parent_id);


--
-- Name: address pk_address; Type: CONSTRAINT; Schema: dbo; Owner: mayocat
--

ALTER TABLE ONLY address
    ADD CONSTRAINT pk_address PRIMARY KEY (address_id);


--
-- Name: agent pk_agent; Type: CONSTRAINT; Schema: dbo; Owner: mayocat
--

ALTER TABLE ONLY agent
    ADD CONSTRAINT pk_agent PRIMARY KEY (entity_id);


--
-- Name: agent_role pk_agent_role; Type: CONSTRAINT; Schema: dbo; Owner: mayocat
--

ALTER TABLE ONLY agent_role
    ADD CONSTRAINT pk_agent_role PRIMARY KEY (agent_id, role);


--
-- Name: article pk_article; Type: CONSTRAINT; Schema: dbo; Owner: mayocat
--

ALTER TABLE ONLY article
    ADD CONSTRAINT pk_article PRIMARY KEY (entity_id);


--
-- Name: attachment pk_attachment; Type: CONSTRAINT; Schema: dbo; Owner: mayocat
--

ALTER TABLE ONLY attachment
    ADD CONSTRAINT pk_attachment PRIMARY KEY (entity_id);


--
-- Name: carrier pk_carrier; Type: CONSTRAINT; Schema: dbo; Owner: mayocat
--

ALTER TABLE ONLY carrier
    ADD CONSTRAINT pk_carrier PRIMARY KEY (id);


--
-- Name: collection pk_collection; Type: CONSTRAINT; Schema: dbo; Owner: mayocat
--

ALTER TABLE ONLY collection
    ADD CONSTRAINT pk_collection PRIMARY KEY (entity_id);


--
-- Name: customer pk_customer; Type: CONSTRAINT; Schema: dbo; Owner: mayocat
--

ALTER TABLE ONLY customer
    ADD CONSTRAINT pk_customer PRIMARY KEY (entity_id);


--
-- Name: entity pk_entity; Type: CONSTRAINT; Schema: dbo; Owner: mayocat
--

ALTER TABLE ONLY entity
    ADD CONSTRAINT pk_entity PRIMARY KEY (id);


--
-- Name: page pk_page; Type: CONSTRAINT; Schema: dbo; Owner: mayocat
--

ALTER TABLE ONLY page
    ADD CONSTRAINT pk_page PRIMARY KEY (entity_id);


--
-- Name: payment_operation pk_payment_operation; Type: CONSTRAINT; Schema: dbo; Owner: mayocat
--

ALTER TABLE ONLY payment_operation
    ADD CONSTRAINT pk_payment_operation PRIMARY KEY (operation_id);


--
-- Name: product pk_product; Type: CONSTRAINT; Schema: dbo; Owner: mayocat
--

ALTER TABLE ONLY product
    ADD CONSTRAINT pk_product PRIMARY KEY (entity_id);


--
-- Name: product_feature pk_product_feature; Type: CONSTRAINT; Schema: dbo; Owner: mayocat
--

ALTER TABLE ONLY product_feature
    ADD CONSTRAINT pk_product_feature PRIMARY KEY (entity_id);


--
-- Name: purchase_order pk_purchase_order; Type: CONSTRAINT; Schema: dbo; Owner: mayocat
--

ALTER TABLE ONLY purchase_order
    ADD CONSTRAINT pk_purchase_order PRIMARY KEY (entity_id);


--
-- Name: tenant pk_tenant; Type: CONSTRAINT; Schema: dbo; Owner: mayocat
--

ALTER TABLE ONLY tenant
    ADD CONSTRAINT pk_tenant PRIMARY KEY (entity_id);


--
-- Name: schema_version schema_version_pk; Type: CONSTRAINT; Schema: dbo; Owner: mayocat
--

ALTER TABLE ONLY schema_version
    ADD CONSTRAINT schema_version_pk PRIMARY KEY (version);


--
-- Name: tenant tenant_default_host_key; Type: CONSTRAINT; Schema: dbo; Owner: mayocat
--

ALTER TABLE ONLY tenant
    ADD CONSTRAINT tenant_default_host_key UNIQUE (default_host);


--
-- Name: thumbnail thumbnail_pk; Type: CONSTRAINT; Schema: dbo; Owner: mayocat
--

ALTER TABLE ONLY thumbnail
    ADD CONSTRAINT thumbnail_pk PRIMARY KEY (attachment_id, source, hint);


--
-- Name: addon_group_index; Type: INDEX; Schema: dbo; Owner: mayocat
--

CREATE INDEX addon_group_index ON addon USING btree (addon_group);


--
-- Name: addon_source_index; Type: INDEX; Schema: dbo; Owner: mayocat
--

CREATE INDEX addon_source_index ON addon USING btree (source);


--
-- Name: agent_email_index; Type: INDEX; Schema: dbo; Owner: mayocat
--

CREATE INDEX agent_email_index ON agent USING btree (email);


--
-- Name: article_publication_date_index; Type: INDEX; Schema: dbo; Owner: mayocat
--

CREATE INDEX article_publication_date_index ON article USING btree (publication_date);


--
-- Name: article_published_index; Type: INDEX; Schema: dbo; Owner: mayocat
--

CREATE INDEX article_published_index ON article USING btree (published);


--
-- Name: attachment_extension_index; Type: INDEX; Schema: dbo; Owner: mayocat
--

CREATE INDEX attachment_extension_index ON attachment USING btree (extension);


--
-- Name: collection_position_index; Type: INDEX; Schema: dbo; Owner: mayocat
--

CREATE INDEX collection_position_index ON collection USING btree ("position");


--
-- Name: collection_product_position_index; Type: INDEX; Schema: dbo; Owner: mayocat
--

CREATE INDEX collection_product_position_index ON collection_product USING btree ("position");


--
-- Name: customer_email_index; Type: INDEX; Schema: dbo; Owner: mayocat
--

CREATE INDEX customer_email_index ON customer USING btree (email);


--
-- Name: entity_list_entity_id_index; Type: INDEX; Schema: dbo; Owner: mayocat
--

CREATE INDEX entity_list_entity_id_index ON entity_list USING gin (entities);


--
-- Name: entity_slug_index; Type: INDEX; Schema: dbo; Owner: mayocat
--

CREATE INDEX entity_slug_index ON entity USING btree (slug);


--
-- Name: entity_tenant_index; Type: INDEX; Schema: dbo; Owner: mayocat
--

CREATE INDEX entity_tenant_index ON entity USING btree (tenant_id);


--
-- Name: entity_type_index; Type: INDEX; Schema: dbo; Owner: mayocat
--

CREATE INDEX entity_type_index ON entity USING btree (type);


--
-- Name: entity_unique_slug_per_type_per_parent_when_tenant_is_null; Type: INDEX; Schema: dbo; Owner: mayocat
--

CREATE UNIQUE INDEX entity_unique_slug_per_type_per_parent_when_tenant_is_null ON entity USING btree (slug, type, parent_id) WHERE (tenant_id IS NULL);


--
-- Name: gateway_customer_data_gateway_index; Type: INDEX; Schema: dbo; Owner: mayocat
--

CREATE INDEX gateway_customer_data_gateway_index ON gateway_customer_data USING btree (gateway);


--
-- Name: gateway_tenant_data_gateway_index; Type: INDEX; Schema: dbo; Owner: mayocat
--

CREATE INDEX gateway_tenant_data_gateway_index ON gateway_tenant_data USING btree (gateway);


--
-- Name: localized_entity_locale; Type: INDEX; Schema: dbo; Owner: mayocat
--

CREATE INDEX localized_entity_locale ON localized_entity USING btree (locale);


--
-- Name: page_position_index; Type: INDEX; Schema: dbo; Owner: mayocat
--

CREATE INDEX page_position_index ON page USING btree ("position");


--
-- Name: page_published_index; Type: INDEX; Schema: dbo; Owner: mayocat
--

CREATE INDEX page_published_index ON page USING btree (published);


--
-- Name: product_feature_feature_slug_index; Type: INDEX; Schema: dbo; Owner: mayocat
--

CREATE INDEX product_feature_feature_slug_index ON product_feature USING btree (feature_slug);


--
-- Name: product_on_shelf_index; Type: INDEX; Schema: dbo; Owner: mayocat
--

CREATE INDEX product_on_shelf_index ON product USING btree (on_shelf);


--
-- Name: product_position_index; Type: INDEX; Schema: dbo; Owner: mayocat
--

CREATE INDEX product_position_index ON product USING btree ("position");


--
-- Name: product_title_fulltext_index; Type: INDEX; Schema: dbo; Owner: mayocat
--

CREATE INDEX product_title_fulltext_index ON product USING gin (lower(m_unaccent((title)::text)) gin_trgm_ops);


--
-- Name: schema_version_ir_idx; Type: INDEX; Schema: dbo; Owner: mayocat
--

CREATE INDEX schema_version_ir_idx ON schema_version USING btree (installed_rank);


--
-- Name: schema_version_s_idx; Type: INDEX; Schema: dbo; Owner: mayocat
--

CREATE INDEX schema_version_s_idx ON schema_version USING btree (success);


--
-- Name: schema_version_vr_idx; Type: INDEX; Schema: dbo; Owner: mayocat
--

CREATE INDEX schema_version_vr_idx ON schema_version USING btree (version_rank);


--
-- Name: tenant_default_host_index; Type: INDEX; Schema: dbo; Owner: mayocat
--

CREATE INDEX tenant_default_host_index ON tenant USING btree (default_host);


--
-- Name: thumbnail_hint_index; Type: INDEX; Schema: dbo; Owner: mayocat
--

CREATE INDEX thumbnail_hint_index ON thumbnail USING btree (hint);


--
-- Name: thumbnail_hint_ratio; Type: INDEX; Schema: dbo; Owner: mayocat
--

CREATE INDEX thumbnail_hint_ratio ON thumbnail USING btree (ratio);


--
-- Name: thumbnail_hint_source; Type: INDEX; Schema: dbo; Owner: mayocat
--

CREATE INDEX thumbnail_hint_source ON thumbnail USING btree (source);


--
-- Name: addon addon_entity_fk; Type: FK CONSTRAINT; Schema: dbo; Owner: mayocat
--

ALTER TABLE ONLY addon
    ADD CONSTRAINT addon_entity_fk FOREIGN KEY (entity_id) REFERENCES entity(id);


--
-- Name: address address_customer_fk; Type: FK CONSTRAINT; Schema: dbo; Owner: mayocat
--

ALTER TABLE ONLY address
    ADD CONSTRAINT address_customer_fk FOREIGN KEY (customer_id) REFERENCES customer(entity_id);


--
-- Name: agent agent_entity_fk; Type: FK CONSTRAINT; Schema: dbo; Owner: mayocat
--

ALTER TABLE ONLY agent
    ADD CONSTRAINT agent_entity_fk FOREIGN KEY (entity_id) REFERENCES entity(id) ON DELETE CASCADE;


--
-- Name: agent_role agent_role_agent_fk; Type: FK CONSTRAINT; Schema: dbo; Owner: mayocat
--

ALTER TABLE ONLY agent_role
    ADD CONSTRAINT agent_role_agent_fk FOREIGN KEY (agent_id) REFERENCES agent(entity_id) ON DELETE CASCADE;


--
-- Name: article article_entity_fk; Type: FK CONSTRAINT; Schema: dbo; Owner: mayocat
--

ALTER TABLE ONLY article
    ADD CONSTRAINT article_entity_fk FOREIGN KEY (entity_id) REFERENCES entity(id) ON DELETE CASCADE;


--
-- Name: article article_featured_image_fk; Type: FK CONSTRAINT; Schema: dbo; Owner: mayocat
--

ALTER TABLE ONLY article
    ADD CONSTRAINT article_featured_image_fk FOREIGN KEY (featured_image_id) REFERENCES entity(id) ON DELETE CASCADE;


--
-- Name: attachment attachment_entity_fk; Type: FK CONSTRAINT; Schema: dbo; Owner: mayocat
--

ALTER TABLE ONLY attachment
    ADD CONSTRAINT attachment_entity_fk FOREIGN KEY (entity_id) REFERENCES entity(id) ON DELETE CASCADE;


--
-- Name: carrier_rule carrier_rule_carrier_fk; Type: FK CONSTRAINT; Schema: dbo; Owner: mayocat
--

ALTER TABLE ONLY carrier_rule
    ADD CONSTRAINT carrier_rule_carrier_fk FOREIGN KEY (carrier_id) REFERENCES carrier(id) ON DELETE CASCADE;


--
-- Name: collection collection_entity_fk; Type: FK CONSTRAINT; Schema: dbo; Owner: mayocat
--

ALTER TABLE ONLY collection
    ADD CONSTRAINT collection_entity_fk FOREIGN KEY (entity_id) REFERENCES entity(id) ON DELETE CASCADE;


--
-- Name: collection collection_featured_image_fk; Type: FK CONSTRAINT; Schema: dbo; Owner: mayocat
--

ALTER TABLE ONLY collection
    ADD CONSTRAINT collection_featured_image_fk FOREIGN KEY (featured_image_id) REFERENCES entity(id) ON DELETE CASCADE;


--
-- Name: collection_product collection_product_collection_entity_fk; Type: FK CONSTRAINT; Schema: dbo; Owner: mayocat
--

ALTER TABLE ONLY collection_product
    ADD CONSTRAINT collection_product_collection_entity_fk FOREIGN KEY (collection_id) REFERENCES entity(id) ON DELETE CASCADE;


--
-- Name: collection_product collection_product_product_entity_fk; Type: FK CONSTRAINT; Schema: dbo; Owner: mayocat
--

ALTER TABLE ONLY collection_product
    ADD CONSTRAINT collection_product_product_entity_fk FOREIGN KEY (product_id) REFERENCES entity(id) ON DELETE CASCADE;


--
-- Name: customer customer_entity_fk; Type: FK CONSTRAINT; Schema: dbo; Owner: mayocat
--

ALTER TABLE ONLY customer
    ADD CONSTRAINT customer_entity_fk FOREIGN KEY (entity_id) REFERENCES entity(id) ON DELETE CASCADE;


--
-- Name: entity_list entity_list_entity_id_fkey; Type: FK CONSTRAINT; Schema: dbo; Owner: mayocat
--

ALTER TABLE ONLY entity_list
    ADD CONSTRAINT entity_list_entity_id_fkey FOREIGN KEY (entity_id) REFERENCES entity(id);


--
-- Name: entity entity_parent_fk; Type: FK CONSTRAINT; Schema: dbo; Owner: mayocat
--

ALTER TABLE ONLY entity
    ADD CONSTRAINT entity_parent_fk FOREIGN KEY (parent_id) REFERENCES entity(id);


--
-- Name: entity entity_tenant_fk; Type: FK CONSTRAINT; Schema: dbo; Owner: mayocat
--

ALTER TABLE ONLY entity
    ADD CONSTRAINT entity_tenant_fk FOREIGN KEY (tenant_id) REFERENCES tenant(entity_id) ON DELETE CASCADE;


--
-- Name: gateway_customer_data gateway_customer_data_customer_fk; Type: FK CONSTRAINT; Schema: dbo; Owner: mayocat
--

ALTER TABLE ONLY gateway_customer_data
    ADD CONSTRAINT gateway_customer_data_customer_fk FOREIGN KEY (customer_id) REFERENCES customer(entity_id) ON DELETE CASCADE;


--
-- Name: gateway_tenant_data gateway_tenant_data_tenant_fk; Type: FK CONSTRAINT; Schema: dbo; Owner: mayocat
--

ALTER TABLE ONLY gateway_tenant_data
    ADD CONSTRAINT gateway_tenant_data_tenant_fk FOREIGN KEY (tenant_id) REFERENCES tenant(entity_id) ON DELETE CASCADE;


--
-- Name: localized_entity localized_entity_entity_id_fkey; Type: FK CONSTRAINT; Schema: dbo; Owner: mayocat
--

ALTER TABLE ONLY localized_entity
    ADD CONSTRAINT localized_entity_entity_id_fkey FOREIGN KEY (entity_id) REFERENCES entity(id) ON DELETE CASCADE;


--
-- Name: purchase_order order_billing_address_entity_fk; Type: FK CONSTRAINT; Schema: dbo; Owner: mayocat
--

ALTER TABLE ONLY purchase_order
    ADD CONSTRAINT order_billing_address_entity_fk FOREIGN KEY (billing_address_id) REFERENCES address(address_id) ON DELETE SET NULL;


--
-- Name: purchase_order order_customer_entity_fk; Type: FK CONSTRAINT; Schema: dbo; Owner: mayocat
--

ALTER TABLE ONLY purchase_order
    ADD CONSTRAINT order_customer_entity_fk FOREIGN KEY (customer_id) REFERENCES entity(id) ON DELETE SET NULL;


--
-- Name: purchase_order order_delivery_address_entity_fk; Type: FK CONSTRAINT; Schema: dbo; Owner: mayocat
--

ALTER TABLE ONLY purchase_order
    ADD CONSTRAINT order_delivery_address_entity_fk FOREIGN KEY (delivery_address_id) REFERENCES address(address_id) ON DELETE SET NULL;


--
-- Name: purchase_order order_entity_fk; Type: FK CONSTRAINT; Schema: dbo; Owner: mayocat
--

ALTER TABLE ONLY purchase_order
    ADD CONSTRAINT order_entity_fk FOREIGN KEY (entity_id) REFERENCES entity(id) ON DELETE CASCADE;


--
-- Name: page page_entity_fk; Type: FK CONSTRAINT; Schema: dbo; Owner: mayocat
--

ALTER TABLE ONLY page
    ADD CONSTRAINT page_entity_fk FOREIGN KEY (entity_id) REFERENCES entity(id) ON DELETE CASCADE;


--
-- Name: page page_featured_image_fk; Type: FK CONSTRAINT; Schema: dbo; Owner: mayocat
--

ALTER TABLE ONLY page
    ADD CONSTRAINT page_featured_image_fk FOREIGN KEY (featured_image_id) REFERENCES entity(id) ON DELETE CASCADE;


--
-- Name: payment_operation payment_operation_order_fk; Type: FK CONSTRAINT; Schema: dbo; Owner: mayocat
--

ALTER TABLE ONLY payment_operation
    ADD CONSTRAINT payment_operation_order_fk FOREIGN KEY (order_id) REFERENCES purchase_order(entity_id) ON DELETE CASCADE;


--
-- Name: product product_entity_fk; Type: FK CONSTRAINT; Schema: dbo; Owner: mayocat
--

ALTER TABLE ONLY product
    ADD CONSTRAINT product_entity_fk FOREIGN KEY (entity_id) REFERENCES entity(id) ON DELETE CASCADE;


--
-- Name: product_feature product_feature_entity_fk; Type: FK CONSTRAINT; Schema: dbo; Owner: mayocat
--

ALTER TABLE ONLY product_feature
    ADD CONSTRAINT product_feature_entity_fk FOREIGN KEY (entity_id) REFERENCES entity(id) ON DELETE CASCADE;


--
-- Name: product product_featured_image_fk; Type: FK CONSTRAINT; Schema: dbo; Owner: mayocat
--

ALTER TABLE ONLY product
    ADD CONSTRAINT product_featured_image_fk FOREIGN KEY (featured_image_id) REFERENCES entity(id) ON DELETE CASCADE;


--
-- Name: tenant tenant_entity_fk; Type: FK CONSTRAINT; Schema: dbo; Owner: mayocat
--

ALTER TABLE ONLY tenant
    ADD CONSTRAINT tenant_entity_fk FOREIGN KEY (entity_id) REFERENCES entity(id) ON DELETE CASCADE;


--
-- Name: tenant tenant_featured_image_fk; Type: FK CONSTRAINT; Schema: dbo; Owner: mayocat
--

ALTER TABLE ONLY tenant
    ADD CONSTRAINT tenant_featured_image_fk FOREIGN KEY (featured_image_id) REFERENCES entity(id) ON DELETE CASCADE;


--
-- Name: thumbnail thumbnail_image_fk; Type: FK CONSTRAINT; Schema: dbo; Owner: mayocat
--

ALTER TABLE ONLY thumbnail
    ADD CONSTRAINT thumbnail_image_fk FOREIGN KEY (attachment_id) REFERENCES attachment(entity_id) ON DELETE CASCADE;


--
-- PostgreSQL database dump complete
--
