-- phpMyAdmin SQL Dump
-- version 5.2.0
-- https://www.phpmyadmin.net/
--
-- Host: 192.168.0.24
-- Generation Time: Jan 07, 2023 at 10:53 PM
-- Server version: 5.7.39
-- PHP Version: 8.0.19

SET SQL_MODE = "NO_AUTO_VALUE_ON_ZERO";
START TRANSACTION;
SET time_zone = "+00:00";


/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8mb4 */;

--
-- Database: `rosariosis`
--

-- --------------------------------------------------------

--
-- Table structure for table `config`
--

CREATE TABLE `config` (
  `school_id` int(11) NOT NULL,
  `title` varchar(100) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `config_value` longtext COLLATE utf8mb4_unicode_520_ci,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

--
-- Dumping data for table `config`
--

INSERT INTO `config` (`school_id`, `title`, `config_value`, `created_at`, `updated_at`) VALUES
(0, 'LOGIN', 'Yes', '2023-01-07 18:06:02', '2023-01-07 18:06:28'),
(0, 'VERSION', '10.6.3', '2023-01-07 18:06:02', NULL),
(0, 'TITLE', 'Rosario Student Information System', '2023-01-07 18:06:02', NULL),
(0, 'NAME', 'RosarioSIS', '2023-01-07 18:06:02', NULL),
(0, 'MODULES', 'a:13:{s:12:\"School_Setup\";b:1;s:8:\"Students\";b:1;s:5:\"Users\";b:1;s:10:\"Scheduling\";b:1;s:6:\"Grades\";b:1;s:10:\"Attendance\";b:1;s:11:\"Eligibility\";b:1;s:10:\"Discipline\";b:1;s:10:\"Accounting\";b:1;s:15:\"Student_Billing\";b:1;s:12:\"Food_Service\";b:1;s:9:\"Resources\";b:1;s:6:\"Custom\";b:1;}', '2023-01-07 18:06:02', NULL),
(0, 'PLUGINS', 'a:1:{s:6:\"Moodle\";b:0;}', '2023-01-07 18:06:02', NULL),
(0, 'THEME', 'FlatSIS', '2023-01-07 18:06:02', NULL),
(0, 'THEME_FORCE', NULL, '2023-01-07 18:06:02', NULL),
(0, 'CREATE_USER_ACCOUNT', NULL, '2023-01-07 18:06:02', NULL),
(0, 'CREATE_STUDENT_ACCOUNT', NULL, '2023-01-07 18:06:02', NULL),
(0, 'CREATE_STUDENT_ACCOUNT_AUTOMATIC_ACTIVATION', NULL, '2023-01-07 18:06:02', NULL),
(0, 'CREATE_STUDENT_ACCOUNT_DEFAULT_SCHOOL', NULL, '2023-01-07 18:06:02', NULL),
(0, 'STUDENTS_EMAIL_FIELD', NULL, '2023-01-07 18:06:02', NULL),
(0, 'DISPLAY_NAME', 'CONCAT(FIRST_NAME,coalesce(NULLIF(CONCAT(\' \',MIDDLE_NAME,\' \'),\'  \'),\' \'),LAST_NAME)', '2023-01-07 18:06:02', NULL),
(1, 'DISPLAY_NAME', 'CONCAT(FIRST_NAME,coalesce(NULLIF(CONCAT(\' \',MIDDLE_NAME,\' \'),\'  \'),\' \'),LAST_NAME)', '2023-01-07 18:06:02', NULL),
(0, 'LIMIT_EXISTING_CONTACTS_ADDRESSES', NULL, '2023-01-07 18:06:02', NULL),
(0, 'FAILED_LOGIN_LIMIT', '30', '2023-01-07 18:06:02', NULL),
(0, 'PASSWORD_STRENGTH', '1', '2023-01-07 18:06:02', NULL),
(0, 'FORCE_PASSWORD_CHANGE_ON_FIRST_LOGIN', NULL, '2023-01-07 18:06:02', NULL),
(0, 'GRADEBOOK_CONFIG_ADMIN_OVERRIDE', NULL, '2023-01-07 18:06:02', NULL),
(0, 'REMOVE_ACCESS_USERNAME_PREFIX_ADD', NULL, '2023-01-07 18:06:02', NULL),
(1, 'SCHOOL_SYEAR_OVER_2_YEARS', 'Y', '2023-01-07 18:06:02', NULL),
(1, 'ATTENDANCE_FULL_DAY_MINUTES', '300', '2023-01-07 18:06:02', NULL),
(1, 'STUDENTS_USE_MAILING', NULL, '2023-01-07 18:06:02', NULL),
(1, 'CURRENCY', '$', '2023-01-07 18:06:02', NULL),
(1, 'DECIMAL_SEPARATOR', '.', '2023-01-07 18:06:02', NULL),
(1, 'THOUSANDS_SEPARATOR', ',', '2023-01-07 18:06:02', NULL),
(1, 'CLASS_RANK_CALCULATE_MPS', NULL, '2023-01-07 18:06:02', NULL);
COMMIT;

/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
