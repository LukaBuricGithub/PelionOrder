# Privacy Policy — Pelion Order

This privacy policy applies to the **Pelion Order** app for mobile devices ("the Application"),
published by **PELION d.o.o.** ("the Service Provider"). The Application is a waiter's ordering
terminal: it is used by staff of a hospitality venue to enter orders and send them to that venue's
own I-Kasa point-of-sale system.

The Application is not intended for use by guests or the general public. It cannot be used at all
without a code issued by a venue's own point-of-sale system.

## What information does the Application obtain and how is it used?

The Application does **not** create user accounts, and it does **not** collect personal information
for marketing, advertising or profiling. There is no registration, and no e-mail address, telephone
number or payment information is ever requested.

To do its job, the Application processes the following:

**1. Venue provisioning data.** When a code displayed by the venue's point-of-sale system is
scanned, the Application stores on the device the venue licence identifier, the device identifier
assigned by that system (e.g. `…-PELIONORDER-3`), the venue name and the device group. This data is
stored only on the device and is used to connect to the correct venue.

**2. Order and table data.** While in use, the Application exchanges the following with the venue's
point-of-sale system: orders entered by the waiter, the venue's price list, its table layout, the
state of tables (occupied, locked, amounts, number of items), and the venue's staff list, which
contains the names and internal codes of employees authorised to use the Application. This data is
business data belonging to the venue.

**3. Data stored on the device.** Orders that have not yet been confirmed by the point-of-sale
system, items typed but not yet sent, the signed-in employee's code, and display preferences are
stored on the device so that nothing is lost if the Application is closed or the connection drops.

**4. Technical connection data.** When the Application connects to the messaging broker, technical
protocol data (such as the device's ephemeral IP address and the device identifier described above)
is transmitted in order to establish and maintain the connection.

The Application does **not** collect crash or usage analytics of its own, and contains no
advertising and no tracking technologies.

## Camera

The Application uses the device camera for one purpose only: to read the QR code shown by the
venue's point-of-sale system when the device is set up. The camera image is processed on the device
in order to decode that code. **No photograph or video is stored on the device, and no image is
transmitted anywhere.** Camera access can be refused or withdrawn at any time in the device
settings; the Application can then no longer be set up for a venue.

## Does the Application collect precise real time location information of the device?

No. The Application does not collect or process any location data.

## Do third parties see and/or have access to information obtained by the Application?

**The venue.** Orders and table data are sent to the point-of-sale system of the venue whose code
was scanned. That venue is the controller of this data; the Service Provider processes it on the
venue's behalf and according to its instructions.

**The messaging broker.** Data travels between the Application and the venue's point-of-sale system
through a messaging broker operated by the Service Provider (MQTT over TLS). Messages are routed
only within the branch belonging to that venue's licence.

**Google LLC.** The code scanner uses Google's ML Kit barcode-scanning library, which runs on the
device. The library sends its own technical usage diagnostics (such as library version, device model
and whether scanning succeeded) to Google. It does not send the camera image, the scanned code or
any of the data described above. Google's privacy notice is available at
<https://firebase.google.com/support/privacy>.

No other third party receives data from the Application. The Service Provider does not sell data and
does not share it for advertising purposes.

## Legal basis and roles

For order and table data, and for the staff list, the **venue is the controller** and the Service
Provider acts as **processor**, under a data processing agreement between them. Processing of
technical connection data necessary to operate the Application is based on the Service Provider's
legitimate interest under Article 6(1)(f) GDPR in providing a functioning and secure service.

## What are my opt-out rights?

- **Uninstalling the Application** stops all data transmission from the device and deletes the data
  stored on it.
- **Scanning a new code** replaces the previously stored venue data on that device.
- Employees whose names appear in a venue's staff list should direct requests concerning their
  personal data to their employer, the venue, as the controller. The Service Provider will assist
  the venue in responding to such requests.
- You may contact the Service Provider at any time at info@pelion.hr.

## How long is data retained?

Data on the device (provisioning data, unsent orders, unsent items, preferences) is kept until the
orders are sent or deleted, a new code is scanned, or the Application is uninstalled. Messages sent
through the broker are held only until the venue's point-of-sale system receives them, and are
deleted after delivery; undelivered messages are discarded when the recipient's session expires.
Data recorded in the venue's point-of-sale system is retained by the venue, under its own policies
and applicable law.

## Children

The Application is a professional tool for hospitality staff and is not intended for children under
16 years of age, or such higher age as required by applicable law. The Service Provider does not
knowingly collect data from children and does not market to them.

## Security

All communication between the Application, the broker and the point-of-sale system is encrypted
(TLS). A device can only connect to the venue whose code it has scanned, and only within that
venue's own branch of the broker. The Service Provider implements reasonable safeguards to protect
its systems and any data it holds. However, no security system is completely secure.

## Data Breach Notification

If a breach occurs involving data processed through the Application, the Service Provider will
notify the affected venues and, where required by applicable law (including Articles 33 and 34
GDPR), the competent supervisory authority and the affected individuals.

## Changes

The Service Provider may update this Privacy Policy from time to time. Material changes will be
announced by publishing the updated Privacy Policy with a new effective date. Previous versions are
kept and are available on request at info@pelion.hr.

This privacy policy is effective as of **[DATUM]**.

## Your Consent

If you voluntarily provide information to the Service Provider and processing is based on consent,
you may withdraw that consent at any time without affecting processing carried out before
withdrawal. For processing based on legitimate interest, you may object at any time as set out in
the "What are my opt-out rights?" section.

## Contact Us

If you have any questions regarding privacy while using the Application, or about these practices,
please contact the Service Provider by e-mail at info@pelion.hr.
