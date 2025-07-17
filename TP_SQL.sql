---------------------------------------------------------------------------
-------CREA DATABASE-------------------------------------------------------
---------------------------------------------------------------------------
CREATE DATABASE Migracion_my
GO
USE [BDD2_TUIA]
GO

CREATE TABLE D_Fecha(
    ID_fecha INT PRIMARY KEY NOT NULL IDENTITY(1,1),
    Fecha DATE NOT NULL UNIQUE,
    Dia INT NOT NULL,
    Mes INT NOT NULL,
    Nombre_mes VARCHAR(50) NOT NULL,
    Dia_del_anio INT NOT NULL,
    Dia_de_semana INT NOT NULL,
    Nombre_dia_de_semana VARCHAR(50) NOT NULL,
    Dias_habiles VARCHAR(50) NOT NULL,
    Feriado VARCHAR(50) NOT NULL,
    Nombre_feriado VARCHAR(50),
    Trimestre INT NOT NULL,
    Semestre INT NOT NULL
);

CREATE TABLE D_Region(
    Region VARCHAR(50) NOT NULL,
    Estado VARCHAR(50) NOT NULL,
    Ciudad VARCHAR(50) NOT NULL,
    Codigo_postal INT NOT NULL PRIMARY KEY
);

CREATE TABLE D_Cliente(
    ID_cliente INT PRIMARY KEY NOT NULL,
    Nombre_cliente VARCHAR(50) NOT NULL,
    Fecha_de_nacimiento  DATE NOT NULL,
    Tipo_de_cliente VARCHAR(50) NOT NULL,
    Codigo_postal INT NOT NULL,
    FOREIGN KEY (Codigo_postal) REFERENCES D_Region(Codigo_postal)
);

CREATE TABLE D_Producto(
    ID_producto INT PRIMARY KEY IDENTITY(1,1),
    Nombre_producto VARCHAR(50) NOT NULL,
    Tipo_de_envase VARCHAR(50) NOT NULL,
);

CREATE TABLE D_Stock(
    ID_Stock INT PRIMARY KEY IDENTITY(1,1),
    ID_producto INT NOT NULL,
    Fecha_stock VARCHAR(50) NOT NULL, 
    Cantidad_stock INT NOT NULL,
    FOREIGN KEY (ID_producto) REFERENCES D_Producto(ID_producto)
);

CREATE TABLE D_Precio(
	ID_Precio INT PRIMARY KEY NOT NULL IDENTITY(1,1),
    ID_Producto INT NOT NULL,
    Fecha DATE NOT NULL,
    Precio FLOAT NOT NULL,
    FOREIGN KEY (ID_Producto) REFERENCES D_Producto(ID_producto)
);

CREATE TABLE D_Empleado(
	ID_empleado INT PRIMARY KEY NOT NULL,
	Nombre_empleado VARCHAR(100) NOT NULL,
	Categoria VARCHAR(50),
	Fecha_ingreso DATE NOT NULL,
	Fecha_de_nacimiento DATE NOT NULL,
	Nivel_educacion VARCHAR(50) NOT NULL,
	Genero VARCHAR(50) NOT NULL,
);

CREATE TABLE D_Descuento (
    ID_descuento INT PRIMARY KEY NOT NULL IDENTITY(1,1),
    Fecha_inicio DATE NOT NULL,
    Fecha_final DATE,
    Porcentaje FLOAT NULL,
    Total_factura FLOAT NULL
);

CREATE TABLE H_Factura_Detalle(
    ID_detalle INT PRIMARY KEY NOT NULL IDENTITY(1,1),
    ID_factura INT NOT NULL,
    ID_producto INT NOT NULL,
    Cantidad INT NOT NULL,
    FOREIGN KEY (ID_factura) REFERENCES H_Factura(ID_factura),
	FOREIGN KEY (ID_producto) REFERENCES D_producto(ID_Producto)
);

CREATE TABLE H_Factura (
    ID_factura INT PRIMARY KEY NOT NULL,
    ID_empleado INT NOT NULL,
    ID_cliente INT NOT NULL,
    ID_branch INT,
    Monto_total FLOAT,
    ID_descuento INT,
    Monto_descuento FLOAT,
    Fecha_de_factura DATE NOT NULL,
    FOREIGN KEY (ID_empleado) REFERENCES D_Empleado(ID_empleado),
    FOREIGN KEY (ID_cliente) REFERENCES D_Cliente(ID_cliente),
    FOREIGN KEY (ID_descuento) REFERENCES D_Descuento(ID_descuento),
    FOREIGN KEY (Fecha_de_factura) REFERENCES D_Fecha(Fecha)
);


--Actualiza el monto sin descuento de c/factura
UPDATE HF
SET HF.Monto_total = COALESCE(Total, 0)
FROM H_Factura HF
JOIN (SELECT HF.ID_factura, COALESCE(SUM(HFD.Cantidad * DP.Precio), 0) AS Total
    FROM H_Factura HF
    LEFT JOIN H_Factura_Detalle HFD ON HF.ID_factura = HFD.ID_factura
    LEFT JOIN D_Producto P ON HFD.ID_producto = P.ID_producto
    LEFT JOIN D_Precio DP ON HFD.ID_producto = DP.ID_Producto AND DP.Fecha = (
            SELECT MAX(DP2.Fecha)
            FROM D_Precio DP2
            WHERE DP2.ID_Producto = DP.ID_Producto AND DP2.Fecha <= HF.Fecha_de_factura
    )
    WHERE DP.Fecha <= HF.Fecha_de_factura OR DP.Fecha IS NULL
    GROUP BY HF.ID_factura
) AS Subquery ON HF.ID_factura = Subquery.ID_factura;

-- Actualiza el monto con descuento de cada factura
WITH DescuentosAplicables AS (
    SELECT HF.ID_factura, HF.Monto_total, HF.Fecha_de_factura, D.ID_descuento AS ID_descuento,
		   D.Porcentaje AS Porcentaje_descuento, HF.Monto_total * (D.Porcentaje / 100.0) AS Monto_descuento_calculado,
           ROW_NUMBER() OVER (PARTITION BY HF.ID_factura ORDER BY D.Porcentaje DESC) AS m_dsc
    FROM H_Factura HF
    LEFT JOIN D_Descuento D ON HF.Monto_total >= D.Total_factura 
          AND HF.Fecha_de_factura BETWEEN D.Fecha_inicio AND ISNULL(D.Fecha_final, '2024-12-31'))

UPDATE HF
SET 
    ID_descuento = DA.ID_descuento,  -- Actualizar con el ID_descuento
    Monto_descuento = HF.Monto_total - DA.Monto_descuento_calculado
FROM H_Factura HF
JOIN DescuentosAplicables DA ON HF.ID_factura = DA.ID_factura
WHERE DA.m_dsc = 1;

--Crea una vista para convertir cm3 a litros
CREATE VIEW V_convertir_a_Litro1 AS
SELECT ROW_NUMBER() OVER (ORDER BY ID_producto) AS ID_incremental,ID_producto,Nombre_producto,Tipo_de_envase,
    CASE 
        WHEN Tipo_de_envase LIKE '% liter' THEN CAST(REPLACE(Tipo_de_envase, ' liter', '') AS FLOAT)
        WHEN Tipo_de_envase LIKE '%cm3 can' THEN CAST(REPLACE(Tipo_de_envase, 'cm3 can', '') AS FLOAT) / 1000
        ELSE NULL
    END AS capacidad_L
FROM D_Producto;

--Crea una vista para realizar el ranking
CREATE VIEW V_Ranking AS
SELECT 
    r.Region,
    r.Estado,
    r.Ciudad,
    p.ID_producto,
    p.Nombre_producto,
    f.Fecha_de_factura,
    SUM(d.Cantidad) AS Total_Productos
FROM H_Factura_Detalle d
JOIN H_Factura f ON d.ID_factura = f.ID_factura
JOIN D_Cliente c ON f.ID_cliente = c.ID_cliente
JOIN D_Region r ON c.Codigo_postal = r.Codigo_postal
JOIN D_Producto p ON d.ID_producto = p.ID_producto
GROUP BY r.Region, r.Estado, r.Ciudad, p.ID_producto, p.Nombre_producto, f.Fecha_de_factura;

--Crea una vista para calcular el tipo de envase
CREATE VIEW V_Envase_edad AS
SELECT 
    c.ID_cliente,
    c.Fecha_de_nacimiento,
    p.Tipo_de_envase,
    CASE 
        WHEN p.Tipo_de_envase LIKE '% liter' THEN 'Botella'
        WHEN p.Tipo_de_envase LIKE '%cm3 can' THEN 'Lata'
        ELSE 'Otro'
    END AS Tipo_Envase,
    SUM(d.Cantidad * v.capacidad_L) AS Total_Litros
FROM H_Factura_Detalle d
JOIN H_Factura f ON d.ID_factura = f.ID_factura
JOIN D_Cliente c ON f.ID_cliente = c.ID_cliente
JOIN D_Producto p ON d.ID_producto = p.ID_producto
JOIN V_convertir_a_Litro1 v ON p.ID_producto = v.ID_producto
GROUP BY c.ID_cliente, c.Fecha_de_nacimiento, p.Tipo_de_envase;


--pruebas
select *
from H_Factura;

DELETE D_Producto;
DBCC CHECKIDENT ('D_Producto', RESEED, 0);
DBCC CHECKIDENT ('D_Producto', NORESEED);


ALTER TABLE D_Producto
ADD Litros FLOAT;

UPDATE D_Producto
SET Tipo_de_envase = 
    CASE 
        WHEN Tipo_de_envase LIKE '%liter%' THEN CAST(SUBSTRING(Tipo_de_envase, 1, CHARINDEX(' ', Tipo_de_envase) - 1) AS FLOAT)
        WHEN Tipo_de_envase LIKE '%cm3 can%' THEN CAST(SUBSTRING(Tipo_de_envase, 1, CHARINDEX(' ', Tipo_de_envase) - 1) AS FLOAT) / 1000
        ELSE 0
    END;

--DESKTOP-IQ0VNJK\SQLEXPRESS
SELECT *
FROM D_Producto;
WHERE Fecha_de_factura IS NULL
   OR ID_factura IS NULL
   OR ID_cliente IS NULL;

WITH LitrosPorCliente AS (
    SELECT
        f.ID_cliente,
        SUM(d.Cantidad * v.capacidad_L) AS Total_Litros
    FROM H_Factura_Detalle d
    JOIN H_Factura f ON d.ID_factura = f.ID_factura
    JOIN V_convertir_a_Litro1 v ON d.ID_producto = v.ID_producto
    GROUP BY f.ID_cliente
)

--EJ 01
SELECT 
    f.ID_cliente,
    f.Fecha_de_factura,
    SUM(d.Cantidad * v.capacidad_L) AS Total_Litros,
    SUM(d.Cantidad) AS Total_Productos
FROM H_Factura_Detalle d
JOIN H_Factura f ON d.ID_factura = f.ID_factura
JOIN V_convertir_a_Litro1 v ON d.ID_producto = v.ID_producto
GROUP BY f.ID_cliente, f.Fecha_de_factura
ORDER BY f.ID_cliente, f.Fecha_de_factura;
--EJ 02
WITH LitrosPorFactura AS (
    SELECT 
        f.ID_cliente,
        f.ID_factura,
        SUM(d.Cantidad * v.capacidad_L) AS Total_Litros
    FROM H_Factura_Detalle d
    JOIN H_Factura f ON d.ID_factura = f.ID_factura
    JOIN V_convertir_a_Litro1 v ON d.ID_producto = v.ID_producto
    GROUP BY f.ID_cliente, f.ID_factura
)

SELECT 
    ID_cliente,
    AVG(Total_Litros) AS Promedio_Litros
FROM LitrosPorFactura
GROUP BY ID_cliente
ORDER BY ID_cliente;
--ej  03
SELECT 
    r.Region,
    r.Estado,
    r.Ciudad,
    p.ID_producto,
    p.Nombre_producto,
    f.Fecha_de_factura,
    SUM(d.Cantidad) AS Total_Productos,
    RANK() OVER (PARTITION BY r.Region, r.Estado, r.Ciudad, f.Fecha_de_factura ORDER BY SUM(d.Cantidad) DESC) AS Producto_Rank
FROM H_Factura_Detalle d
JOIN H_Factura f ON d.ID_factura = f.ID_factura
JOIN D_Cliente c ON f.ID_cliente = c.ID_cliente
JOIN D_Region r ON c.Codigo_postal = r.Codigo_postal
JOIN D_Producto p ON d.ID_producto = p.ID_producto
GROUP BY r.Region, r.Estado, r.Ciudad, p.ID_producto, p.Nombre_producto, f.Fecha_de_factura
ORDER BY r.Region, r.Estado, r.Ciudad, Producto_Rank;
--ej 04

--ej 05
SELECT 
    f.ID_cliente,
    SUM(d.Cantidad * v.capacidad_L) AS Total_Litros_Septiembre
FROM H_Factura_Detalle d
JOIN H_Factura f ON d.ID_factura = f.ID_factura
JOIN D_Producto p ON d.ID_producto = p.ID_producto
JOIN V_convertir_a_Litro1 v ON p.ID_producto = v.ID_producto
WHERE p.Nombre_producto = 'Energy Drink'
AND MONTH(f.Fecha_de_factura) = 9
GROUP BY f.ID_cliente
ORDER BY Total_Litros_Septiembre DESC;
--EJ 06
SELECT 
    c.ID_cliente,
    DATEDIFF(YEAR, c.Fecha_de_nacimiento, GETDATE()) AS Edad,
    CASE 
        WHEN p.Tipo_de_envase LIKE '% liter' THEN 'Botella'
        WHEN p.Tipo_de_envase LIKE '%cm3 can' THEN 'Lata'
        ELSE 'Otro'
    END AS Tipo_Envase,
    SUM(d.Cantidad * v.capacidad_L) AS Total_Litros
FROM H_Factura_Detalle d
JOIN H_Factura f ON d.ID_factura = f.ID_factura
JOIN D_Cliente c ON f.ID_cliente = c.ID_cliente
JOIN D_Producto p ON d.ID_producto = p.ID_producto
JOIN V_convertir_a_Litro1 v ON p.ID_producto = v.ID_producto
GROUP BY c.ID_cliente, c.Fecha_de_nacimiento, p.Tipo_de_envase
ORDER BY Edad;


--comparacion ej 1 y 2
SELECT 
    f.ID_cliente,
    SUM(d.Cantidad * v.capacidad_L) AS Total_Litros
FROM H_Factura_Detalle d
JOIN H_Factura f ON d.ID_factura = f.ID_factura
JOIN V_convertir_a_Litro1 v ON d.ID_producto = v.ID_producto
GROUP BY f.ID_cliente
ORDER BY Total_Litros DESC;

WITH LitrosPorFactura AS (
    SELECT 
        f.ID_cliente,
        f.ID_factura,
        SUM(d.Cantidad * v.capacidad_L) AS Total_Litros
    FROM H_Factura_Detalle d
    JOIN H_Factura f ON d.ID_factura = f.ID_factura
    JOIN V_convertir_a_Litro1 v ON d.ID_producto = v.ID_producto
    GROUP BY f.ID_cliente, f.ID_factura
)

SELECT 
    ID_cliente,
    AVG(Total_Litros) AS Promedio_Litros
FROM LitrosPorFactura
GROUP BY ID_cliente
ORDER BY Promedio_Litros DESC;

--DESKTOP-IQ0VNJK\SQLEXPRESS
CREATE VIEW V_Ventas_Trimestrales AS
SELECT 
    YEAR(Fecha_de_factura) AS Anio,
    DATEPART(QUARTER, Fecha_de_factura) AS Trimestre,
    SUM(Monto_total) AS Ventas_Trimestre
FROM 
    H_Factura
GROUP BY 
    YEAR(Fecha_de_factura), DATEPART(QUARTER, Fecha_de_factura);









SELECT 
    c.ID_cliente,
    DATEDIFF(YEAR, c.Fecha_de_nacimiento, GETDATE()) AS Edad,
    CASE 
        WHEN p.Tipo_de_envase LIKE '% liter' THEN 'Botella'
        WHEN p.Tipo_de_envase LIKE '%cm3 can' THEN 'Lata'
        ELSE 'Otro'
    END AS Tipo_Envase,
    SUM(d.Cantidad * v.capacidad_L) AS Total_Litros
FROM H_Factura_Detalle d
JOIN H_Factura f ON d.ID_factura = f.ID_factura
JOIN D_Cliente c ON f.ID_cliente = c.ID_cliente
JOIN D_Producto p ON d.ID_producto = p.ID_producto
JOIN V_convertir_a_Litro1 v ON p.ID_producto = v.ID_producto
GROUP BY c.ID_cliente, c.Fecha_de_nacimiento, p.Tipo_de_envase
ORDER BY Edad;

